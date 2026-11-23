load test_helper

setup() {
  setup_lab
  export WINDOWS_MOUNT_PREFIX="$TEST_TMP/no-windows/"
  LAB="$REPO_ROOT/lab.sh"
  LIVE="$TEST_TMP/acme/acme-platform"
}
teardown() { teardown_lab; }

mkstacks() {
  local s
  for s in "$@"; do mkdir -p "$LIVE/terraform/$s"; done
}

fake_tf() { # fake_tf <rc-for-destroy-of-stack-or-empty> stacks...
  local s
  for s in "$@"; do
    fake_response terraform "-chdir=$LIVE/terraform/$s init -input=false" 0
    fake_response terraform "-chdir=$LIVE/terraform/$s destroy -auto-approve -input=false" 0
    fake_response terraform "-chdir=$LIVE/terraform/$s apply -auto-approve -input=false" 0
  done
}

fake_sub() { fake_response az "account show --query id -o tsv" 0 "00000000-0000-0000-0000-000000000000"; }

mark_done() { printf '%s\t1\t2\n' "$1" >>"$LAB_HOME/progress"; }

# stateful_gh: a gh on PATH that knows resume's run bookkeeping. The dispatched terraform.yml run
# is 333 (listed once "workflow run terraform.yml ... stacks=all" happened); run view answers
# from $STATE/view (one state per line, consumed in order; the last one repeats). Every other gh
# call goes to the static fakes (fake_response).
stateful_gh() {
  # A bounded wait: a test that never sees its run fails instead of hanging.
  export STATE="$TEST_TMP/state" RESUME_POLL_SECONDS=0 RESUME_RUN_TIMEOUT=20
  mkdir -p "$STATE" "$TEST_TMP/bin"
  echo "completed success" >"$STATE/view"
  cat >"$TEST_TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
r="-R learner/acme-platform"
case "$*" in
  "run list $r --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId")
    echo "gh $*" >>"$FAKE_LOG"
    [[ -f "$STATE/dispatched" ]] && echo 333
    echo 200 ;;
  "workflow run terraform.yml $r --ref main -f stacks=all")
    echo "gh $*" >>"$FAKE_LOG"
    touch "$STATE/dispatched" ;;
  "run view 333 $r --json status,conclusion --jq "*)
    echo "gh run view 333" >>"$FAKE_LOG"
    head -n1 "$STATE/view"
    if [[ "$(wc -l <"$STATE/view")" -gt 1 ]]; then sed -i 1d "$STATE/view"; fi ;;
  *) exec "$REPO_ROOT/tests/fakes/_fake" gh "$@" ;;
esac
SH
  chmod +x "$TEST_TMP/bin/gh"
  export PATH="$TEST_TMP/bin:$PATH"
}

# stub_ansible_lib: a TRACKS_DIR whose tracks/ansible/lib scripts only log their name, exiting
# with KV_RC (keyvault-prereqs.sh) / RR_RC (runner-register.sh), default 0.
stub_ansible_lib() {
  local lib="$TEST_TMP/tracks/ansible/lib"
  mkdir -p "$lib"
  printf '#!/usr/bin/env bash\necho keyvault-prereqs.sh >>"$FAKE_LOG"\nexit "${KV_RC:-0}"\n' >"$lib/keyvault-prereqs.sh"
  printf '#!/usr/bin/env bash\necho runner-register.sh >>"$FAKE_LOG"\nexit "${RR_RC:-0}"\n' >"$lib/runner-register.sh"
  export TRACKS_DIR="$TEST_TMP/tracks"
}

# live_ansible <files...>: ansible/ in the live repo with these (empty) files, and an empty venv.
live_ansible() {
  local f
  mkdir -p "$LIVE/ansible/.venv/bin"
  : >"$LIVE/ansible/.venv/bin/activate"
  for f in "$@"; do
    mkdir -p "$(dirname "$LIVE/$f")"
    : >"$LIVE/$f"
  done
}

@test "pause destroys stacks in order and skips missing" {
  mkstacks shared env-dev teams/payments
  fake_tf shared env-dev teams/payments
  run "$LAB" pause
  [ "$status" -eq 0 ]
  [ -f "$LAB_HOME/paused" ]
  expected="terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/env-dev init -input=false
terraform -chdir=$LIVE/terraform/env-dev destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared destroy -auto-approve -input=false"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume dispatches the terraform workflow in the live repo and waits for that run" {
  stateful_gh
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  : >"$LAB_HOME/paused"
  printf 'queued \nin_progress \ncompleted success\n' >"$STATE/view"
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  [[ "$output" == *"waiting for terraform.yml run 333"* ]]
  expected="gh run list -R learner/acme-platform --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId
gh workflow run terraform.yml -R learner/acme-platform --ref main -f stacks=all
gh run list -R learner/acme-platform --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId
gh run view 333
gh run view 333
gh run view 333"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume waits through apply-prod without approving it, and says so once" {
  stateful_gh
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  printf 'waiting \nwaiting \nin_progress \ncompleted success\n' >"$STATE/view"
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ "$(grep -c "waits for your approval of apply-prod" <<<"$output")" -eq 1 ]
  [[ "$(cat "$FAKE_LOG")" != *pending_deployments* ]]
}

@test "a failed terraform run keeps the lab paused and skips the Ansible steps" {
  stateful_gh
  stub_ansible_lib
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  live_ansible ansible/site.yml
  : >"$LAB_HOME/paused"
  echo "completed failure" >"$STATE/view"
  run "$LAB" resume
  [ "$status" -eq 1 ]
  [ -f "$LAB_HOME/paused" ]
  [[ "$output" == *"terraform.yml run 333 ended: failure"* ]]
  [[ "$(cat "$FAKE_LOG")" != *keyvault-prereqs* ]]
}

@test "resume before an-15: Key Vault prerequisites, then site.yml from ansible/.venv" {
  stateful_gh
  stub_ansible_lib
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  live_ansible ansible/site.yml
  fake_response ansible-playbook "site.yml" 0
  : >"$LAB_HOME/paused"
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  [ "$(tail -n 2 "$FAKE_LOG")" = "keyvault-prereqs.sh
ansible-playbook site.yml" ]
  [ "$(grep -n "gh run view 333" "$FAKE_LOG" | tail -n1 | cut -d: -f1)" -lt "$(grep -n keyvault-prereqs "$FAKE_LOG" | cut -d: -f1)" ]
}

@test "resume from an-15: runner-register.sh before ansible.yml is dispatched (from an-16)" {
  stateful_gh
  stub_ansible_lib
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  live_ansible ansible/site.yml ansible/runner.yml .github/workflows/ansible.yml
  fake_response gh "workflow run ansible.yml -R learner/acme-platform --ref main -f env=dev" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ "$(tail -n 3 "$FAKE_LOG")" = "keyvault-prereqs.sh
runner-register.sh
gh workflow run ansible.yml -R learner/acme-platform --ref main -f env=dev" ]
  [[ "$(cat "$FAKE_LOG")" != *"ansible-playbook"* ]]
}

@test "resume at an-15 (runner, no Ansible pipeline yet) registers the runner and dispatches nothing" {
  stateful_gh
  stub_ansible_lib
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  live_ansible ansible/site.yml ansible/runner.yml
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$FAKE_LOG")" = "runner-register.sh" ]
}

@test "failing Ansible steps keep the lab paused" {
  stateful_gh
  stub_ansible_lib
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  live_ansible ansible/site.yml ansible/runner.yml
  : >"$LAB_HOME/paused"
  KV_RC=1 run "$LAB" resume
  [ "$status" -eq 1 ]
  [ -f "$LAB_HOME/paused" ]
  [[ "$output" == *"keyvault-prereqs.sh failed"* ]]
  [[ "$(cat "$FAKE_LOG")" != *runner-register* ]]
  rm -f "$STATE/dispatched" # each resume dispatches a new run
  KV_RC=3 run "$LAB" resume
  [ "$status" -eq 3 ]
  [ -f "$LAB_HOME/paused" ]
  rm -f "$STATE/dispatched"
  RR_RC=1 run "$LAB" resume
  [ "$status" -eq 1 ]
  [ -f "$LAB_HOME/paused" ]
  [[ "$output" == *"runner-register.sh failed"* ]]
}

@test "resume applies locally before pipelines exist" {
  stub_ansible_lib
  mkstacks shared env-prod teams/payments
  fake_tf shared env-prod teams/payments
  : >"$LAB_HOME/paused"
  live_ansible ansible/site.yml
  fake_response ansible-playbook "site.yml" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  expected="terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared apply -auto-approve -input=false
terraform -chdir=$LIVE/terraform/env-prod init -input=false
terraform -chdir=$LIVE/terraform/env-prod apply -auto-approve -input=false
terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments apply -auto-approve -input=false
keyvault-prereqs.sh
ansible-playbook site.yml"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume runs no Ansible step without ansible/ in the live repo" {
  stub_ansible_lib
  mark_done an-02
  mkstacks shared
  fake_tf shared
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *ansible* ]]
}

@test "grade refuses while paused but offline still works" {
  : >"$LAB_HOME/paused"
  run "$LAB" grade
  [ "$status" -eq 7 ]
  [[ "$output" == *"lab is paused — ./lab.sh resume first"* ]]
  run "$LAB" grade --all
  [ "$status" -eq 7 ]
  run "$LAB" grade --offline
  [ "$status" -ne 7 ]
}

@test "nuke requires typed prefix" {
  mkstacks shared
  run "$LAB" nuke <<<"wrong"
  [ "$status" -eq 6 ]
  run "$LAB" nuke <<<$'acme\nnope'
  [ "$status" -eq 6 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "nuke deletes state RG after stacks" {
  fake_sub
  mkstacks shared landing-zone bootstrap teams/payments
  fake_tf shared landing-zone bootstrap teams/payments
  mark_done tf-01
  : >"$LAB_HOME/paused"
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 0 "pid-123"
  fake_response az "role assignment delete --assignee pid-123 --yes" 0
  # the learner's own Key Vault Secrets Officer on the subscription (tf-21), found by principal,
  # role and exact scope
  fake_response az "ad signed-in-user show --query id -o tsv" 0 "uid-me"
  fake_response az "role assignment list --assignee uid-me --scope /subscriptions/00000000-0000-0000-0000-000000000000 --role Key Vault Secrets Officer --query [?scope=='/subscriptions/00000000-0000-0000-0000-000000000000'].id -o tsv" 0 \
    "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/ra-1"
  fake_response az "role assignment delete --ids /subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/ra-1 --yes" 0
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  fake_response gh "repo delete learner/acme-platform --yes" 0
  # tf-31: the payments team's group is vended by bootstrap, which nuke never destroys
  fake_response az "group list --tag vended_by=bootstrap --query [?starts_with(name, 'rg-acme-')].name -o tsv" 0 "rg-acme-payments"
  fake_response az "group exists -n rg-acme-payments -o tsv" 0 true
  fake_response az "group delete -n rg-acme-payments --yes" 0
  run "$LAB" nuke <<<$'acme\nnuke\ny\nn'
  [ "$status" -eq 0 ]
  expected="az account show --query id -o tsv
terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/landing-zone init -input=false
terraform -chdir=$LIVE/terraform/landing-zone destroy -auto-approve -input=false
az group list --tag vended_by=bootstrap --query [?starts_with(name, 'rg-acme-')].name -o tsv
az group exists -n rg-acme-payments -o tsv
az group delete -n rg-acme-payments --yes
az identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv
az role assignment delete --assignee pid-123 --yes
az ad signed-in-user show --query id -o tsv
az role assignment list --assignee uid-me --scope /subscriptions/00000000-0000-0000-0000-000000000000 --role Key Vault Secrets Officer --query [?scope=='/subscriptions/00000000-0000-0000-0000-000000000000'].id -o tsv
az role assignment delete --ids /subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/ra-1 --yes
az group delete -n rg-acme-tfstate --yes
gh repo delete learner/acme-platform --yes"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
  [[ "$output" == *"Delete GitHub repo learner/acme-platform? [y/N]"* ]]
  [[ "$output" == *"Delete GitHub repo learner/acme-terraform-modules? [y/N]"* ]]
  [[ "$output" == *"Delete GitHub repo learner/acme-payments-app? [y/N]"* ]]
  [ ! -e "$LAB_HOME/progress" ]
  [ ! -e "$LAB_HOME/paused" ]
}

@test "nuke skips role cleanup when identity is missing" {
  fake_sub
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 3
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  run "$LAB" nuke <<<$'acme\nnuke\nn\nn'
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *"role assignment delete --assignee"* ]]
}

@test "nuke stops before group delete when a destroy fails" {
  fake_sub
  mkstacks shared
  fake_response terraform "-chdir=$LIVE/terraform/shared init -input=false" 0
  fake_response terraform "-chdir=$LIVE/terraform/shared destroy -auto-approve -input=false" 1
  run "$LAB" nuke <<<$'acme\nnuke\ny\ny'
  [ "$status" -eq 1 ]
  [[ "$output" == *"shared"* ]]
  [[ "$(cat "$FAKE_LOG")" != *"group delete"* ]]
}

@test "cost sums usage" {
  start="$(date +%Y-%m-01)"; end="$(date +%F)"
  fake_response az "consumption usage list --start-date $start --end-date $end -o json" 0 \
    '[{"pretaxCost":1.5,"currency":"SEK"},{"pretaxCost":"2.256","currency":"SEK"}]'
  run "$LAB" cost
  [ "$status" -eq 0 ]
  [ "$output" = "month to date: 3.76 SEK of budget 300" ]
}

@test "cost tolerates unsupported API" {
  start="$(date +%Y-%m-01)"; end="$(date +%F)"
  fake_response az "consumption usage list --start-date $start --end-date $end -o json" 1
  run "$LAB" cost
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost API not available for this subscription type; check the portal"* ]]
}

@test "cost prints two decimals for whole numbers and empty usage" {
  start="$(date +%Y-%m-01)"; end="$(date +%F)"
  fake_response az "consumption usage list --start-date $start --end-date $end -o json" 0     '[{"pretaxCost":5,"currency":"SEK"},{"pretaxCost":7,"currency":"SEK"}]'
  run "$LAB" cost
  [ "$output" = "month to date: 12.00 SEK of budget 300" ]
  fake_response az "consumption usage list --start-date $start --end-date $end -o json" 0 '[]'
  run "$LAB" cost
  [ "$output" = "month to date: 0.00 ? of budget 300" ]
}

@test "failed resume keeps the lab paused" {
  mkstacks shared
  : >"$LAB_HOME/paused"
  fake_response terraform "-chdir=$LIVE/terraform/shared init -input=false" 0
  fake_response terraform "-chdir=$LIVE/terraform/shared apply -auto-approve -input=false" 1
  run "$LAB" resume
  [ "$status" -ne 0 ]
  [ -f "$LAB_HOME/paused" ]
}

@test "nuke refuses on the wrong subscription" {
  mkstacks shared
  fake_response az "account show --query id -o tsv" 0 "99999999-9999-9999-9999-999999999999"
  run "$LAB" nuke <<<$'acme
nuke
y
y'
  [ "$status" -eq 4 ]
  [[ "$output" == *"az is on subscription 99999999-9999-9999-9999-999999999999, lab is 00000000-0000-0000-0000-000000000000 — az account set -s 00000000-0000-0000-0000-000000000000"* ]]
  [[ "$(cat "$FAKE_LOG")" != *destroy* ]]
  [[ "$(cat "$FAKE_LOG")" != *"group delete"* ]]
}

@test "children do not consume the repo-delete answers" {
  fake_sub
  mkdir -p "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $*" >>"$FAKE_LOG"
cat >/dev/null
SH
  cat >"$TEST_TMP/bin/az" <<'SH'
#!/usr/bin/env bash
echo "az $*" >>"$FAKE_LOG"
[[ "$1 $2" == "account show" ]] && echo "00000000-0000-0000-0000-000000000000"
[[ "$1" == identity ]] && exit 3
cat >/dev/null
exit 0
SH
  cat >"$TEST_TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
cat >/dev/null
SH
  chmod +x "$TEST_TMP/bin/"*
  export PATH="$TEST_TMP/bin:$PATH"
  mkstacks shared
  run "$LAB" nuke <<<$'acme
nuke
y
n
'
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" == *"gh repo delete learner/acme-platform --yes"* ]]
  [[ "$(cat "$FAKE_LOG")" != *"acme-terraform-modules --yes"* ]]
  [[ "$(cat "$FAKE_LOG")" == *"destroy -auto-approve -input=false"* ]]
}

@test "pause hands destroys values for the variables CI sets from repo variables" {
  export HOME="$TEST_TMP/home"
  mkdir -p "$TEST_TMP/bin" "$HOME"
  cat >"$TEST_TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $* ip=$TF_VAR_learner_ip key=${TF_VAR_ssh_public_key%% *} mail=$TF_VAR_budget_email" >>"$FAKE_LOG"
SH
  chmod +x "$TEST_TMP/bin/terraform"
  export PATH="$TEST_TMP/bin:$PATH"
  mkstacks shared
  run "$LAB" pause
  [ "$status" -eq 0 ]
  grep -q "destroy -auto-approve -input=false ip=203.0.113.10 key=ssh-ed25519 mail=nuke@example.invalid" "$FAKE_LOG"
  # the learner's own public key wins over the placeholder
  mkdir -p "$HOME/.ssh"
  echo "ssh-rsa AAAAB3Nza learner" >"$HOME/.ssh/acme_lab.pub"
  : >"$FAKE_LOG"
  run "$LAB" pause
  [ "$status" -eq 0 ]
  grep -q "destroy -auto-approve -input=false ip=203.0.113.10 key=ssh-rsa" "$FAKE_LOG"
}

@test "resume imports the app image into the new registry before the full run" {
  stateful_gh
  mkdir -p "$LIVE/.github/workflows" "$LIVE/terraform/shared" "$LIVE/terraform/env-dev"
  : >"$LIVE/.github/workflows/terraform.yml"
  printf '      image = "${data.azurerm_container_registry.shared.login_server}/hello:1.0"\n' >"$LIVE/terraform/env-dev/container-app.tf"
  : >"$LAB_HOME/paused"
  fake_response gh "workflow run terraform.yml -R learner/acme-platform --ref main -f stacks=shared" 0
  fake_response az "acr show -n acracmeabc123 --query provisioningState -o tsv" 0 Succeeded
  fake_response az "acr repository show -n acracmeabc123 --image hello:1.0 -o none" 1
  fake_response az "acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  expected="gh workflow run terraform.yml -R learner/acme-platform --ref main -f stacks=shared
az acr show -n acracmeabc123 --query provisioningState -o tsv
az acr repository show -n acracmeabc123 --image hello:1.0 -o none
az acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none
gh run list -R learner/acme-platform --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId
gh workflow run terraform.yml -R learner/acme-platform --ref main -f stacks=all
gh run list -R learner/acme-platform --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId
gh run view 333"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume stays paused when the app image can't be imported" {
  mkdir -p "$LIVE/.github/workflows" "$LIVE/terraform/shared" "$LIVE/terraform/env-dev"
  : >"$LIVE/.github/workflows/terraform.yml"
  printf '      image = "x.azurecr.io/hello:1.0"\n' >"$LIVE/terraform/env-dev/container-app.tf"
  : >"$LAB_HOME/paused"
  fake_response gh "workflow run terraform.yml -R learner/acme-platform --ref main -f stacks=shared" 0
  fake_response az "acr show -n acracmeabc123 --query provisioningState -o tsv" 0 Succeeded
  fake_response az "acr repository show -n acracmeabc123 --image hello:1.0 -o none" 1
  fake_response az "acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none" 1
  run "$LAB" resume
  [ "$status" -ne 0 ]
  [ -f "$LAB_HOME/paused" ]
  [[ "$(cat "$FAKE_LOG")" != *"stacks=all"* ]]
}

@test "pause leaves observability running (tf-29: the workspace survives a pause)" {
  mkstacks shared observability landing-zone
  fake_tf shared observability landing-zone
  run "$LAB" pause
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *observability* ]]
  [[ "$(cat "$FAKE_LOG")" != *landing-zone* ]]
}

@test "pause disables and resume enables drift.yml (tf-27)" {
  mkstacks shared
  fake_tf shared
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/drift.yml"
  fake_response gh "workflow disable drift.yml -R learner/acme-platform" 0
  run "$LAB" pause
  [ "$status" -eq 0 ]
  [ "$(head -n1 "$FAKE_LOG")" = "gh workflow disable drift.yml -R learner/acme-platform" ]
  : >"$FAKE_LOG"
  : >"$LIVE/.github/workflows/terraform.yml"
  stateful_gh
  fake_response gh "workflow enable drift.yml -R learner/acme-platform" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$FAKE_LOG")" = "gh workflow enable drift.yml -R learner/acme-platform" ]
  [ ! -e "$LAB_HOME/paused" ]
}

@test "nuke deletes tf-26's click-ops group when it was never imported, and asks about the team repo" {
  fake_sub
  mkdir -p "$LAB_HOME/snapshots"
  printf 'id
time
' >"$LAB_HOME/snapshots/tf-26.ids"
  fake_response az "group exists -n rg-acme-legacy -o tsv" 0 "true"
  fake_response az "group delete -n rg-acme-legacy --yes" 0
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 3
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  fake_response gh "repo delete learner/acme-payments-app --yes" 0
  run "$LAB" nuke <<<$'acme
nuke
n
n
y'
  [ "$status" -eq 0 ]
  grep -qx "az group delete -n rg-acme-legacy --yes" "$FAKE_LOG"
  grep -qx "gh repo delete learner/acme-payments-app --yes" "$FAKE_LOG"
  ! grep -q "repo delete learner/acme-platform" "$FAKE_LOG"
}

@test "nuke deletes groups bootstrap vended before their team stack exists (tag vended_by)" {
  fake_sub
  fake_response az "group list --tag vended_by=bootstrap --query [?starts_with(name, 'rg-acme-')].name -o tsv" 0 "rg-acme-payments"
  fake_response az "group exists -n rg-acme-payments -o tsv" 0 true
  fake_response az "group delete -n rg-acme-payments --yes" 0
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 3
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  run "$LAB" nuke <<<$'acme\nnuke\nn\nn\nn'
  [ "$status" -eq 0 ]
  grep -qx "az group delete -n rg-acme-payments --yes" "$FAKE_LOG"
  [ ! -d "$LIVE/terraform/teams" ]
}
