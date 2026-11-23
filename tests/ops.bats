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

@test "resume dispatches workflow when present" {
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  : >"$LAB_HOME/paused"
  fake_response gh "workflow run terraform.yml --ref main -f stacks=all" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  [ "$(cat "$FAKE_LOG")" = "gh workflow run terraform.yml --ref main -f stacks=all" ]
}

@test "resume dispatches ansible workflow past an-16" {
  mkdir -p "$LIVE/.github/workflows"
  : >"$LIVE/.github/workflows/terraform.yml"
  mark_done an-16
  fake_response gh "workflow run terraform.yml --ref main -f stacks=all" 0
  fake_response gh "workflow run ansible.yml --ref main -f env=dev" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$FAKE_LOG")" = "gh workflow run ansible.yml --ref main -f env=dev" ]
}

@test "resume applies locally before pipelines exist" {
  mkstacks shared env-prod observability
  fake_tf shared env-prod observability
  : >"$LAB_HOME/paused"
  mark_done an-02
  mkdir -p "$LIVE/ansible"
  fake_response ansible-playbook "-i inventory site.yml" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  expected="terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared apply -auto-approve -input=false
terraform -chdir=$LIVE/terraform/env-prod init -input=false
terraform -chdir=$LIVE/terraform/env-prod apply -auto-approve -input=false
terraform -chdir=$LIVE/terraform/observability init -input=false
terraform -chdir=$LIVE/terraform/observability apply -auto-approve -input=false
ansible-playbook -i inventory site.yml"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume runs no ansible without ansible progress" {
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
  run "$LAB" nuke <<<$'acme\nnuke\ny\nn'
  [ "$status" -eq 0 ]
  expected="az account show --query id -o tsv
terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared destroy -auto-approve -input=false
terraform -chdir=$LIVE/terraform/landing-zone init -input=false
terraform -chdir=$LIVE/terraform/landing-zone destroy -auto-approve -input=false
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
  mkdir -p "$LIVE/.github/workflows" "$LIVE/terraform/shared" "$LIVE/terraform/env-dev"
  : >"$LIVE/.github/workflows/terraform.yml"
  printf '      image = "${data.azurerm_container_registry.shared.login_server}/hello:1.0"\n' >"$LIVE/terraform/env-dev/container-app.tf"
  : >"$LAB_HOME/paused"
  fake_response gh "workflow run terraform.yml --ref main -f stacks=shared" 0
  fake_response az "acr show -n acracmeabc123 --query provisioningState -o tsv" 0 Succeeded
  fake_response az "acr repository show -n acracmeabc123 --image hello:1.0 -o none" 1
  fake_response az "acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none" 0
  fake_response gh "workflow run terraform.yml --ref main -f stacks=all" 0
  run "$LAB" resume
  [ "$status" -eq 0 ]
  [ ! -e "$LAB_HOME/paused" ]
  expected="gh workflow run terraform.yml --ref main -f stacks=shared
az acr show -n acracmeabc123 --query provisioningState -o tsv
az acr repository show -n acracmeabc123 --image hello:1.0 -o none
az acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none
gh workflow run terraform.yml --ref main -f stacks=all"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
}

@test "resume stays paused when the app image can't be imported" {
  mkdir -p "$LIVE/.github/workflows" "$LIVE/terraform/shared" "$LIVE/terraform/env-dev"
  : >"$LIVE/.github/workflows/terraform.yml"
  printf '      image = "x.azurecr.io/hello:1.0"\n' >"$LIVE/terraform/env-dev/container-app.tf"
  : >"$LAB_HOME/paused"
  fake_response gh "workflow run terraform.yml --ref main -f stacks=shared" 0
  fake_response az "acr show -n acracmeabc123 --query provisioningState -o tsv" 0 Succeeded
  fake_response az "acr repository show -n acracmeabc123 --image hello:1.0 -o none" 1
  fake_response az "acr import --name acracmeabc123 --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0 -o none" 1
  run "$LAB" resume
  [ "$status" -ne 0 ]
  [ -f "$LAB_HOME/paused" ]
  [[ "$(cat "$FAKE_LOG")" != *"stacks=all"* ]]
}
