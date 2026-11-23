load test_helper

# Phase 4 (tf-26 ... tf-31) incident and catchup scripts, against the fake az/gh/terraform.

setup() {
  setup_lab
  set -a
  # shellcheck source=/dev/null
  source "$LAB_HOME/config.env"
  set +a
  TT="$REPO_ROOT/tracks/terraform"
  BLOB="--auth-mode login --account-name stacmetfstateabc123 --container-name tfstate"
  mkdir -p "$LAB_HOME/snapshots"
}
teardown() { teardown_lab; }

lockinfo() { # lockinfo <id>: the base64 lock info the azurerm backend writes
  printf '{"ID":"%s","Operation":"OperationTypeApply","Who":"x@y"}' "$1" | base64 -w0
}

@test "tf-28 catchup releases the incident's lock like force-unlock" {
  printf 'lock-1\n100\n' >"$LAB_HOME/snapshots/tf-28.lock"
  fake_response az "storage blob show $BLOB --name env-dev.tfstate --query properties.lease.state -o tsv" 0 leased
  fake_response az "storage blob metadata show $BLOB --name env-dev.tfstate -o json" 0 "{\"terraformlockid\": \"$(lockinfo lock-1)\"}"
  fake_response az "storage blob metadata update $BLOB --name env-dev.tfstate --lease-id lock-1 -o none" 0
  fake_response az "storage blob lease release $BLOB --blob-name env-dev.tfstate --lease-id lock-1 -o none" 0
  run bash "$TT/28-state-lock/catchup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"released the stale lock lock-1"* ]]
  update=$(grep -n "metadata update" "$FAKE_LOG" | cut -d: -f1)
  release=$(grep -n "lease release" "$FAKE_LOG" | cut -d: -f1)
  [ "$update" -lt "$release" ]
}

@test "tf-28 catchup leaves a lock held by a real run alone" {
  printf 'lock-1\n100\n' >"$LAB_HOME/snapshots/tf-28.lock"
  fake_response az "storage blob show $BLOB --name env-dev.tfstate --query properties.lease.state -o tsv" 0 leased
  fake_response az "storage blob metadata show $BLOB --name env-dev.tfstate -o json" 0 "{\"terraformlockid\": \"$(lockinfo other-run)\"}"
  run bash "$TT/28-state-lock/catchup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"locked by other-run"* ]]
  ! grep -q "lease release\|metadata update" "$FAKE_LOG"
}

@test "tf-28 catchup does nothing without the incident's snapshot" {
  run bash "$TT/28-state-lock/catchup.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "tf-28 setup refuses while a real run holds the lock, and locks only once" {
  fake_response az "storage blob show $BLOB --name env-dev.tfstate --query properties.lease.state -o tsv" 0 leased
  run bash "$TT/28-state-lock/setup.sh"
  [ "$status" -eq 1 ]
  [ ! -e "$LAB_HOME/snapshots/tf-28.lock" ]
  printf 'lock-1\n100\n' >"$LAB_HOME/snapshots/tf-28.lock"
  : >"$FAKE_LOG"
  run bash "$TT/28-state-lock/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Error acquiring the state lock"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "tf-27 setup injects the drift once and never again" {
  mkdir -p "$TEST_TMP/bin"
  printf '#!/usr/bin/env bash
echo "az $*" >>"$FAKE_LOG"
' >"$TEST_TMP/bin/az"
  chmod +x "$TEST_TMP/bin/az"
  export PATH="$TEST_TMP/bin:$PATH"
  run bash "$TT/27-drift/setup.sh"
  [ "$status" -eq 0 ]
  [ -s "$LAB_HOME/snapshots/tf-27.start" ]
  grep -qx "az group update -n rg-acme-dev --set tags.owner=ops-oncall -o none" "$FAKE_LOG"
  grep -q "^az network nsg rule create -g rg-acme-dev --nsg-name nsg-acme-dev-app -n AllowAll-Temp " "$FAKE_LOG"
  [[ "$output" == *"open to the whole internet"* ]]
  : >"$FAKE_LOG"
  run bash "$TT/27-drift/setup.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "tf-26 catchup imports what is missing and moves what has another address" {
  mkdir -p "$LIVE_DIR/terraform/landing-zone"
  echo 'resource "azurerm_storage_account" "legacy" {}' >"$LIVE_DIR/terraform/landing-zone/legacy.tf"
  lz="-chdir=terraform/landing-zone"
  fake_response terraform "$lz init -input=false" 0
  fake_response terraform "$lz state pull" 0 \
    '{"resources":[{"mode":"managed","type":"azurerm_storage_account","name":"finance","instances":[{"attributes":{"name":"stacmelegacyabc123"}}]}]}'
  fake_response az "group exists -n rg-acme-legacy -o tsv" 0 true
  fake_response az "storage account show -g rg-acme-legacy -n stacmelegacyabc123 -o none" 0
  fake_response terraform "$lz import -input=false -lock-timeout=5m azurerm_resource_group.legacy /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-legacy" 0
  fake_response terraform "$lz state mv -lock-timeout=5m azurerm_storage_account.finance azurerm_storage_account.legacy" 0
  cd "$LIVE_DIR"
  run bash "$TT/26-import/catchup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"imported rg-acme-legacy"* ]]
  [[ "$output" == *"moved azurerm_storage_account.finance to azurerm_storage_account.legacy"* ]]
}

@test "tf-26 catchup leaves resources that don't exist to the pipeline" {
  mkdir -p "$LIVE_DIR/terraform/landing-zone"
  echo 'resource "azurerm_storage_account" "legacy" {}' >"$LIVE_DIR/terraform/landing-zone/legacy.tf"
  lz="-chdir=terraform/landing-zone"
  fake_response terraform "$lz init -input=false" 0
  fake_response terraform "$lz state pull" 0 '{"resources":[]}'
  fake_response az "group exists -n rg-acme-legacy -o tsv" 0 false
  cd "$LIVE_DIR"
  run bash "$TT/26-import/catchup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rg-acme-legacy doesn't exist; the pipeline creates it"* ]]
  ! grep -q " import \| state mv " "$FAKE_LOG"
}

@test "tf-26 catchup does nothing when landing-zone doesn't declare the account" {
  mkdir -p "$LIVE_DIR/terraform/landing-zone"
  cd "$LIVE_DIR"
  run bash "$TT/26-import/catchup.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "tf-31 catchup creates the team repo once" {
  fake_response gh "repo view learner/acme-payments-app --json name" 1
  fake_response gh "repo create learner/acme-payments-app --public --description Payments team's service (platform lab, tf-31)" 0
  fake_response gh "api repos/learner/acme-payments-app/actions/oidc/customization/sub --jq .sub_claim_prefix // empty" 0 "repo:learner@1/acme-payments-app@2"
  cd "$LIVE_DIR"
  run bash "$TT/31-self-service/catchup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"created the team repo learner/acme-payments-app"* ]]
  ! grep -q "PUT" "$FAKE_LOG"
}

@test "ci_workflow_wait dispatches another workflow on main and waits for its run" {
  export CI_POLL_SECONDS=0 STATE="$TEST_TMP/state"
  mkdir -p "$STATE" "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
case "$*" in
  "run list -R o/r --workflow drift.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId")
    [[ -f "$STATE/dispatched" ]] && echo 9
    echo 5 ;;
  "workflow run drift.yml -R o/r --ref main") touch "$STATE/dispatched" ;;
  "run view 9 -R o/r --json status,conclusion --jq "*) echo "completed success" ;;
  "run list -R o/r --workflow terraform.yml --branch main --status waiting --json databaseId --jq .[].databaseId") ;;
  *) echo "unexpected: gh $*" >&2; exit 1 ;;
esac
SH
  chmod +x "$TEST_TMP/bin/gh"
  export PATH="$TEST_TMP/bin:$PATH"
  # shellcheck source=/dev/null
  source "$TT/lib/ci-dispatch.sh"
  run ci_workflow_wait o/r drift.yml tf-27
  [ "$status" -eq 0 ]
  [[ "$output" == *"tf-27: drift.yml run 9 succeeded"* ]]
}
