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
    fake_response terraform "-chdir=$LIVE/terraform/$s destroy -auto-approve" 0
    fake_response terraform "-chdir=$LIVE/terraform/$s apply -auto-approve -input=false" 0
  done
}

mark_done() { printf '%s\t1\t2\n' "$1" >>"$LAB_HOME/progress"; }

@test "pause destroys stacks in order and skips missing" {
  mkstacks shared env-dev teams/payments
  fake_tf shared env-dev teams/payments
  run "$LAB" pause
  [ "$status" -eq 0 ]
  [ -f "$LAB_HOME/paused" ]
  expected="terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments destroy -auto-approve
terraform -chdir=$LIVE/terraform/env-dev init -input=false
terraform -chdir=$LIVE/terraform/env-dev destroy -auto-approve
terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared destroy -auto-approve"
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
  mkstacks shared landing-zone bootstrap teams/payments
  fake_tf shared landing-zone bootstrap teams/payments
  mark_done tf-01
  : >"$LAB_HOME/paused"
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 0 "pid-123"
  fake_response az "role assignment delete --assignee pid-123 --yes" 0
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  fake_response gh "repo delete learner/acme-platform --yes" 0
  run "$LAB" nuke <<<$'acme\nnuke\ny\nn'
  [ "$status" -eq 0 ]
  expected="terraform -chdir=$LIVE/terraform/teams/payments init -input=false
terraform -chdir=$LIVE/terraform/teams/payments destroy -auto-approve
terraform -chdir=$LIVE/terraform/shared init -input=false
terraform -chdir=$LIVE/terraform/shared destroy -auto-approve
terraform -chdir=$LIVE/terraform/landing-zone init -input=false
terraform -chdir=$LIVE/terraform/landing-zone destroy -auto-approve
az identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv
az role assignment delete --assignee pid-123 --yes
az group delete -n rg-acme-tfstate --yes
gh repo delete learner/acme-platform --yes"
  [ "$(cat "$FAKE_LOG")" = "$expected" ]
  [[ "$output" == *"Delete GitHub repo learner/acme-platform? [y/N]"* ]]
  [[ "$output" == *"Delete GitHub repo learner/acme-terraform-modules? [y/N]"* ]]
  [ ! -e "$LAB_HOME/progress" ]
  [ ! -e "$LAB_HOME/paused" ]
}

@test "nuke skips role cleanup when identity is missing" {
  fake_response az "identity show -g rg-acme-tfstate -n id-acme-github-ci --query principalId -o tsv" 3
  fake_response az "group delete -n rg-acme-tfstate --yes" 0
  run "$LAB" nuke <<<$'acme\nnuke\nn\nn'
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *"role assignment"* ]]
}

@test "nuke stops before group delete when a destroy fails" {
  mkstacks shared
  fake_response terraform "-chdir=$LIVE/terraform/shared init -input=false" 0
  fake_response terraform "-chdir=$LIVE/terraform/shared destroy -auto-approve" 1
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
