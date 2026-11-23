load test_helper

setup() {
  setup_lab
  export WINDOWS_MOUNT_PREFIX="$TEST_TMP/no-windows/"
  export NO_COLOR=1
  LAB="$REPO_ROOT/lab.sh"
  LINT="$REPO_ROOT/tests/lint-tracks.sh"
  VALIDATE="$REPO_ROOT/tests/validate-reference.sh"
}
teardown() { teardown_lab; }

# lint_copy: a writable copy of the demo track in $TEST_TMP/tracks (TRACKS_DIR points there).
lint_copy() {
  mkdir -p "$TEST_TMP/tracks"
  cp -r "$REPO_ROOT/tests/fixtures/tracks/demo" "$TEST_TMP/tracks/demo"
  export TRACKS_DIR="$TEST_TMP/tracks"
}

@test "lint passes the demo fixture track" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/tracks"
  run "$LINT" demo
  [ "$status" -eq 0 ]
}

@test "lint with no tracks prints no tracks" {
  export TRACKS_DIR="$TEST_TMP/empty"
  mkdir -p "$TRACKS_DIR"
  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == "no tracks" ]]
}

@test "lint catches missing file" {
  lint_copy
  rm "$TEST_TMP/tracks/demo/01-first/hint.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"01-first: missing hint.md"* ]]
}

@test "lint catches missing front matter key and unknown requires" {
  lint_copy
  sed -i '/^title:/d; s/^requires:.*/requires: [nope-99]/' "$TEST_TMP/tracks/demo/02-second/task.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"02-second: front matter key title missing"* ]]
  [[ "$output" == *"02-second: requires unknown id nope-99"* ]]
}

@test "lint catches checks.sh without check call, shellcheck finding and CRLF" {
  lint_copy
  printf '#!/usr/bin/env bash\necho $UNQUOTED_X $(ls)\nrm $1\n' >"$TEST_TMP/tracks/demo/01-first/checks.sh"
  printf 'bad\r\nline\r\n' >"$TEST_TMP/tracks/demo/02-second/hint.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"01-first: checks.sh has no check/check_code call"* ]]
  [[ "$output" == *"01-first: shellcheck: checks.sh"* ]]
  [[ "$output" == *"02-second: CRLF line endings in hint.md"* ]]
}

@test "lint catches unknown token" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/01-first/reference/live"
  echo 'name = "{{BOGUS}}-{{PREFIX}}"' >"$TEST_TMP/tracks/demo/01-first/reference/live/main.tf"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"01-first: unknown template token {{BOGUS}} in reference/live/main.tf"* ]]
}

@test "lint catches banned sku but honours lint-allow" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/01-first/reference/live"
  echo 'sku = "Premium"' >"$TEST_TMP/tracks/demo/01-first/reference/live/main.tf"
  echo 'Do not use Bastion here. lint-allow: banned' >>"$TEST_TMP/tracks/demo/01-first/solution.md"
  echo 'Use AzureFirewall.' >>"$TEST_TMP/tracks/demo/02-second/solution.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"01-first: banned string Premium in reference/live/main.tf"* ]]
  [[ "$output" == *"02-second: banned string AzureFirewall in solution.md"* ]]
  [[ "$output" != *"Bastion"* ]]
}

@test "lint checks resource names in task.md against the naming table" {
  lint_copy
  echo 'Create `rg-acme-hub`, `vnet-acme-hub`, `st{{PREFIX}}tfstate{{SUFFIX}}` and `kv-acme-dev-abc123`.' >>"$TEST_TMP/tracks/demo/01-first/task.md"
  run "$LINT" demo
  [ "$status" -eq 0 ]
  echo 'Also create `rg-acme-hubb` and `vnet-acme-staging`.' >>"$TEST_TMP/tracks/demo/01-first/task.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"01-first: resource name rg-acme-hubb in task.md does not match the naming table"* ]]
  [[ "$output" == *"vnet-acme-staging"* ]]
}

@test "selftest offline passes a consistent track" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline good
  [ "$status" -eq 0 ]
  [[ "$output" == *"st-01"* && "$output" == *"st-02"* ]]
  [ ! -e "$LAB_HOME/progress.tsv" ]
}

@test "selftest offline honours --from and --to" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline good --from st-02 --to st-02
  [ "$status" -eq 0 ]
  [[ "$output" != *"st-01"* ]]
  [[ "$output" == *"st-02"* ]]
}

@test "selftest offline lists tasks without check_code as n/a" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline nocheck
  [ "$status" -eq 0 ]
  [[ "$output" == *"n/a"* ]]
}

@test "selftest offline flags check that passes before task" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline passbefore
  [ "$status" -eq 1 ]
  [[ "$output" == *"pb-01"*"passes before the task"* ]]
}

@test "selftest offline flags check that fails after task" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline failafter
  [ "$status" -eq 1 ]
  [[ "$output" == *"fa-01"*"fails after the task"* ]]
}

@test "live selftest refuses without permission variable" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  unset SELFTEST_I_HAVE_PERMISSION
  run "$LAB" selftest good
  [ "$status" -eq 8 ]
  [[ "$output" == *"SELFTEST_I_HAVE_PERMISSION=1"* ]]
  [[ "$output" == *"costs money"* ]]
  [ ! -s "$FAKE_LOG" ]
}

# --- validate-reference (real terraform, no fakes) ---------------------------------------

vr_setup() {
  command -v terraform >/dev/null || skip "terraform not on PATH"
  export PATH="${PATH#"$REPO_ROOT"/tests/fakes:}"
  export TRACKS_DIR="$TEST_TMP/vr"
  local d="$TRACKS_DIR/vr/01-x"
  mkdir -p "$d/reference/live/terraform/stack"
  printf -- '---\nid: vr-01\ntitle: X\ntarget_minutes: 5\nrequires: []\n---\n# X\n' >"$d/task.md"
  VR_TF="$d/reference/live/terraform/stack/main.tf"
}

@test "validate-reference passes a provider-free terraform stack" {
  vr_setup
  command -v tflint >/dev/null || skip "tflint not on PATH"
  command -v trivy >/dev/null || skip "trivy not on PATH"
  cat >"$VR_TF" <<'TF'
terraform {
  required_version = ">= 1.6"
}

resource "terraform_data" "demo" {
  input = "{{PREFIX}}"
}

output "demo" {
  value = terraform_data.demo.output
}
TF
  run "$VALIDATE" vr-01 --no-molecule
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fmt"* && "$output" == *"validate"* ]]
}

@test "validate-reference fails a misformatted terraform file" {
  vr_setup
  printf 'resource "terraform_data" "demo" {\ninput    =    "x"\n}\n' >"$VR_TF"
  run "$VALIDATE" vr-01 --no-molecule
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"fmt"* ]]
}

# --- fix round 1 ------------------------------------------------------------------------

@test "lint flags a banned string in a large file" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/01-first/reference/live"
  f="$TEST_TMP/tracks/demo/01-first/reference/live/big.tf"
  echo 'sku = "Premium"' >"$f"
  awk 'BEGIN { for (i = 0; i < 20000; i++) print "filler filler filler filler" }' >>"$f"
  [ "$(wc -c <"$f")" -gt 300000 ]
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"banned string Premium in reference/live/big.tf"* ]]
}

@test "lint flags banned resource types" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/01-first/reference/live"
  echo 'resource "azurerm_bastion_host" "b" {}' >"$TEST_TMP/tracks/demo/01-first/reference/live/b.tf"
  echo 'resource "azurerm_lb" "l" {}' >"$TEST_TMP/tracks/demo/01-first/reference/live/l.tf"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"banned string azurerm_bastion_host in reference/live/b.tf"* ]]
  [[ "$output" == *"banned string azurerm_lb in reference/live/l.tf"* ]]
}

@test "lint allows the backend's use_azuread_auth but flags the azuread provider" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/01-first/reference/live"
  printf '%s\n' 'terraform {' '  backend "azurerm" {' '    use_azuread_auth = true' '  }' '}' \
    >"$TEST_TMP/tracks/demo/01-first/reference/live/v.tf"
  echo 'Set `use_azuread_auth = true` in the backend.' >>"$TEST_TMP/tracks/demo/01-first/task.md"
  run "$LINT" demo
  [ "$status" -eq 0 ]
  echo 'resource "azuread_group" "g" {}' >"$TEST_TMP/tracks/demo/02-second/solution.md"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"02-second: banned string azuread_ in solution.md"* ]]
  [[ "$output" != *"01-first"* ]]
}

@test "selftest offline builds the full before tree for the capstone" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/capstonetracks"
  run "$LAB" selftest --offline
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cap-01"*"fail"*"pass"*"ok"* ]]
}

@test "selftest offline does not reuse a stale before tree" {
  # tracks run ansible, capstone, terraform: tf-01 comes last and must start from an empty tree
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/capstonetracks"
  run "$LAB" selftest --offline
  [ "$status" -eq 0 ]
  [[ "$output" == *"tf-01"*"fail"*"pass"*"ok"* ]]
}

@test "selftest rejects unknown or reversed ranges before running anything" {
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/selftesttracks"
  run "$LAB" selftest --offline good --to nope-1
  [ "$status" -eq 2 ]
  [[ "$output" != *"st-01"* ]]
  run "$LAB" selftest --offline good --from nope-1
  [ "$status" -eq 2 ]
  run "$LAB" selftest --offline good --from st-02 --to st-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"before"* ]]
  [[ "$output" != *"ok"* ]]
}

# shims: ansible tools that log their arguments (VALIDATE_SHIM_DIR takes priority over real tools)
ansible_fixture() {
  command -v awk >/dev/null
  export PATH="${PATH#"$REPO_ROOT"/tests/fakes:}"
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export TRACKS_DIR="$TEST_TMP/an"
  AN="$TRACKS_DIR/an/01-x/reference/live/ansible"
  mkdir -p "$AN/inventory" "$AN/collections"
  printf -- '---\nid: an-01\ntitle: X\ntarget_minutes: 5\nrequires: []\n---\n# X\n' >"$TRACKS_DIR/an/01-x/task.md"
  printf -- '---\n- name: Demo\n  hosts: all\n  tasks: []\n' >"$AN/site.yml"
  printf -- '---\nall:\n  hosts:\n    h1:\n' >"$AN/static.yml"
  printf -- '---\nall:\n  hosts:\n    h2:\n' >"$AN/inventory/hosts.yml"
  export SHIM_LOG="$TEST_TMP/shim.log"
  : >"$SHIM_LOG"
  export VALIDATE_SHIM_DIR="$TEST_TMP/shims"
  mkdir -p "$VALIDATE_SHIM_DIR"
  for t in yamllint ansible-lint ansible-playbook ansible-galaxy; do
    printf '#!/usr/bin/env bash\necho "%s $* [collections=${ANSIBLE_COLLECTIONS_PATH:-}]" >>"$SHIM_LOG"\n' "$t" >"$VALIDATE_SHIM_DIR/$t"
    chmod +x "$VALIDATE_SHIM_DIR/$t"
  done
}

@test "validate-reference does not syntax-check inventories as playbooks" {
  ansible_fixture
  run "$VALIDATE" an-01 --no-molecule
  [ "$status" -eq 0 ]
  grep -q 'ansible-playbook --syntax-check -i localhost, .*site.yml' "$SHIM_LOG"
  [ "$(grep -c 'ansible-playbook' "$SHIM_LOG")" -eq 1 ]
}

@test "validate-reference installs ansible collections from requirements.yml" {
  ansible_fixture
  printf 'collections:\n  - name: ansible.posix\n' >"$AN/collections/requirements.yml"
  run "$VALIDATE" an-01 --no-molecule
  [ "$status" -eq 0 ]
  grep -q 'ansible-galaxy collection install -r .*requirements.yml -p .*platform-practice/collections' "$SHIM_LOG"
  grep -q 'ansible-playbook .*collections=.*platform-practice/collections' "$SHIM_LOG"
}

@test "validate-reference rejects terraform tests without mock_provider" {
  vr_setup
  command -v tflint >/dev/null || skip "tflint not on PATH"
  command -v trivy >/dev/null || skip "trivy not on PATH"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nresource "terraform_data" "demo" {\n  input = "x"\n}\n' >"$VR_TF"
  mkdir -p "$(dirname "$VR_TF")/tests"
  printf 'run "plain" {\n  command = plan\n}\n' >"$(dirname "$VR_TF")/tests/plain.tftest.hcl"
  run "$VALIDATE" vr-01 --no-molecule
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no mock_provider"* ]]
}

@test "validate-reference rejects a commented-out mock_provider" {
  vr_setup
  command -v tflint >/dev/null || skip "tflint not on PATH"
  command -v trivy >/dev/null || skip "trivy not on PATH"
  printf 'terraform {
  required_version = ">= 1.6"
}

resource "terraform_data" "demo" {
  input = "x"
}
' >"$VR_TF"
  mkdir -p "$(dirname "$VR_TF")/tests"
  printf '# mock_provider "azurerm" {}
run "plain" {
  command = plan
}
' >"$(dirname "$VR_TF")/tests/plain.tftest.hcl"
  run "$VALIDATE" vr-01 --no-molecule
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no mock_provider"* ]]
}

# --- validate-reference: modules repo sources (tf-19/tf-20) --------------------------------

# vr_module_fixture: vr-01 with a provider-free module at reference/modules/mod.
vr_module_fixture() {
  vr_setup
  VR_REF="$TRACKS_DIR/vr/01-x/reference"
  mkdir -p "$VR_REF/modules/mod"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nresource "terraform_data" "m" {\n  input = "x"\n}\n\noutput "id" {\n  value = terraform_data.m.id\n}\n' \
    >"$VR_REF/modules/mod/main.tf"
}

# vr_stack <name> <module path> <ref>: a stack calling the modules repo source.
vr_stack() {
  mkdir -p "$VR_REF/live/terraform/$1"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nmodule "m" {\n  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//%s?ref=%s"\n}\n' "$2" "$3" \
    >"$VR_REF/live/terraform/$1/main.tf"
}

@test "validate-reference rewrites modules repo sources to the local reference module" {
  vr_module_fixture
  command -v tflint >/dev/null || skip "tflint not on PATH"
  command -v trivy >/dev/null || skip "trivy not on PATH"
  rm -rf "$VR_REF/live/terraform/stack"
  vr_stack stack mod v1.0.0
  run "$VALIDATE" vr-01 --no-molecule
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"module source live/terraform/stack/main.tf: mod?ref=v1.0.0 -> ../../../modules/mod"* ]]
  [[ "$output" == *"ok    init live/terraform/stack"* ]]
  [[ "$output" == *"ok    validate live/terraform/stack"* ]]
  [[ "$output" == *"ok    validate modules/mod"* ]]
}

# vr_release_fixture: vr-01 releases v1 of mod (no inputs), vr-02 releases v2 (required input x).
# vr-02's dev stack pins v2 (passes x), its prod stack still pins v1 (passes nothing): prod only
# validates against v1, so it proves the older pin is resolved to vr-01's release.
vr_release_fixture() {
  vr_module_fixture
  rm -rf "$VR_REF/live/terraform/stack"
  VR2="$TRACKS_DIR/vr/02-y/reference"
  mkdir -p "$VR2/modules/mod" "$TRACKS_DIR/vr/lib"
  printf -- '---\nid: vr-02\ntitle: Y\ntarget_minutes: 5\nrequires: [vr-01]\n---\n# Y\n' >"$TRACKS_DIR/vr/02-y/task.md"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nvariable "x" {\n  type = string\n}\n\nresource "terraform_data" "m" {\n  input = var.x\n}\n\noutput "id" {\n  value = terraform_data.m.id\n}\n' \
    >"$VR2/modules/mod/main.tf"
  mkdir -p "$VR2/live/terraform/dev" "$VR2/live/terraform/prod"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nmodule "m" {\n  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//mod?ref=v2.0.0"\n  x      = "dev"\n}\n' \
    >"$VR2/live/terraform/dev/main.tf"
  printf 'terraform {\n  required_version = ">= 1.6"\n}\n\nmodule "m" {\n  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//mod?ref=v1.0.0"\n}\n' \
    >"$VR2/live/terraform/prod/main.tf"
  printf '# test release table\nv1.0.0 vr-01\nv2.0.0 vr-02\n' >"$TRACKS_DIR/vr/lib/module-releases.txt"
}

@test "validate-reference validates an older-major pin against the releasing task's module" {
  vr_release_fixture
  command -v tflint >/dev/null || skip "tflint not on PATH"
  command -v trivy >/dev/null || skip "trivy not on PATH"
  run "$VALIDATE" vr-02 --no-molecule
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"release v1.0.0: the modules tree of vr-01's reference"* ]]
  [[ "$output" == *"live/terraform/prod/main.tf: mod?ref=v1.0.0 -> ../../../releases/v1.0.0/modules/mod"* ]]
  [[ "$output" == *"live/terraform/dev/main.tf: mod?ref=v2.0.0 -> ../../../modules/mod"* ]]
  [[ "$output" == *"ok    validate live/terraform/prod"* ]]
  [[ "$output" == *"ok    validate live/terraform/dev"* ]]
  [[ "$output" != *"skip  live"* ]]
}

@test "validate-reference fails on an older-major pin missing from the release table" {
  vr_release_fixture
  printf 'v2.0.0 vr-02\n' >"$TRACKS_DIR/vr/lib/module-releases.txt"
  run "$VALIDATE" vr-02 --no-molecule
  [ "$status" -ne 0 ]
  [[ "$output" == *"pins mod?ref=v1.0.0"*"module-releases.txt"* ]]
}

@test "validate-reference fails when a pinned module is not in the reference" {
  vr_module_fixture
  rm -rf "$VR_REF/live/terraform/stack"
  vr_stack stack nope v1.0.0
  run "$VALIDATE" vr-01 --no-molecule
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no reference module at modules/nope"* ]]
}

@test "lint treats a track's lib/ as shared helpers: shellcheck, not task files" {
  lint_copy
  mkdir -p "$TEST_TMP/tracks/demo/lib"
  printf '# shellcheck shell=bash\nhelper() { echo "$1"; }\n' >"$TEST_TMP/tracks/demo/lib/helper.sh"
  run "$LINT" demo
  [ "$status" -eq 0 ]
  printf 'bad() { rm $1; }\n' >>"$TEST_TMP/tracks/demo/lib/helper.sh"
  run "$LINT" demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib: shellcheck: helper.sh"* ]]
  [[ "$output" != *"missing task.md"* ]]
}
