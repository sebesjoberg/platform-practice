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
