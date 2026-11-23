load test_helper

setup() {
  setup_lab
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/gradetracks"
  export WINDOWS_MOUNT_PREFIX="$TEST_TMP/no-windows/"
  LAB="$REPO_ROOT/lab.sh"
  export NO_COLOR=1
}
teardown() { teardown_lab; }

fake_login() {
  fake_response az "account show --query id -o tsv" 0 "00000000-0000-0000-0000-000000000000"
  fake_response gh "auth status" 0
}

@test "pass and fail are reported with reason" {
  run "$LAB" grade g-01
  [ "$status" -eq 1 ]
  [[ "$output" == *"✓ PASS  good one"* ]]
  [[ "$output" == *"✗ FAIL  bad one"* ]]
  [[ "$output" == *"    → the bad reason"* ]]
  [[ "$output" == *"1/2 passed"* ]]
}

@test "pipefail fails a check whose first command fails" {
  run "$LAB" grade g-03
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ FAIL  pf"* ]]
}

@test "hanging check times out" {
  GRADE_TIMEOUT=2 run "$LAB" grade g-04
  [ "$status" -eq 1 ]
  [[ "$output" == *"→ timed out"* ]]
}

@test "stdin-reading check does not eat the loop" {
  run "$LAB" grade g-05
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ PASS  second runs"* ]]
  [[ "$output" == *"2/2 passed"* ]]
}

@test "preflight aborts on wrong subscription" {
  fake_response az "account show --query id -o tsv" 0 "ffffffff-0000-0000-0000-000000000000"
  fake_response gh "auth status" 0
  run "$LAB" grade g-07
  [ "$status" -eq 4 ]
  [[ "$output" == *"az not logged in to the lab subscription (az login; az account set -s …)"* ]]
}

@test "preflight aborts when gh is not authenticated" {
  fake_response az "account show --query id -o tsv" 0 "00000000-0000-0000-0000-000000000000"
  fake_response gh "auth status" 1
  run "$LAB" grade g-07
  [ "$status" -eq 4 ]
}

@test "code-only task skips preflight" {
  run "$LAB" grade g-06
  [ "$status" -eq 0 ]
  if grep -q "^az" "$FAKE_LOG"; then false; fi
}

@test "all-pass marks finished and prints timing" {
  fake_login
  printf 'g-02\t%s\t\n' "$(($(date +%s) - 180))" >"$LAB_HOME/progress"
  run "$LAB" grade g-02
  [ "$status" -eq 0 ]
  [[ "$output" == *"2/2 passed — took 3 min (target 10)"* ]]
  grep -qP '^g-02\t\d+\t\d+$' "$LAB_HOME/progress"
}

@test "no recorded start prints took ?" {
  run "$LAB" grade g-06
  [[ "$output" == *"took ? min (target 5)"* ]]
}

@test "unknown id exits 2" {
  run "$LAB" grade nope
  [ "$status" -eq 2 ]
}

@test "grade --all reports regression" {
  LIVE="$TEST_TMP/acme/acme-platform"
  touch "$LIVE/marker.txt"
  run "$LAB" grade g-09
  [ "$status" -eq 0 ]
  before="$(cat "$LAB_HOME/progress")"
  run "$LAB" grade --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"no regressions"* ]]
  rm "$LIVE/marker.txt"
  run "$LAB" grade --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"regressions: g-09"* ]]
  [ "$before" = "$(cat "$LAB_HOME/progress")" ]
}

@test "offline runs only check_code" {
  run "$LAB" grade --offline g-08
  [ "$status" -eq 0 ]
  [[ "$output" == *"1/1 passed"* ]]
  [[ "$output" != *"cloudy"* ]]
  [ ! -s "$FAKE_LOG" ]
  if progress_has_g08; then false; fi
}

progress_has_g08() { grep -q '^g-08' "$LAB_HOME/progress" 2>/dev/null; }

@test "checks.sh ending in a false statement still prints summary" {
  run "$LAB" grade g-10
  [ "$status" -eq 0 ]
  [[ "$output" == *"1/1 passed"* ]]
}

@test "checks.sh with syntax error reports load failure" {
  run "$LAB" grade g-11
  [ "$status" -eq 1 ]
  [[ "$output" == *"g-11: checks.sh failed to load"* ]]
}

@test "preflight aborts when az is not logged in" {
  fake_response az "account show --query id -o tsv" 1
  fake_response gh "auth status" 0
  run "$LAB" grade g-07
  [ "$status" -eq 4 ]
  [[ "$output" == *"az not logged in to the lab subscription"* ]]
  [[ "$output" != *"PASS"* && "$output" != *"FAIL"* ]]
}

@test "colour is emitted when forced and suppressed by NO_COLOR" {
  run env -u NO_COLOR GRADE_FORCE_COLOR=1 bash -c 'source "$1/lib/checks-api.sh"; x="$(_grade_color 32 hi)"; printf %q "$x"' _ "$REPO_ROOT"
  [[ "$output" == *"\E[32m"* || "$output" == *$'\033'* ]]
  run env NO_COLOR=1 GRADE_FORCE_COLOR=1 bash -c 'source "$1/lib/checks-api.sh"; x="$(_grade_color 32 hi)"; printf %s "$x"' _ "$REPO_ROOT"
  [ "$output" = "hi" ]
}

@test "check fails with reason when LIVE_DIR is unset" {
  run env -u LIVE_DIR GRADE_RESULTS="$TEST_TMP/res" bash -c 'set -euo pipefail; source "$1/lib/checks-api.sh"; _grade_run n true r; echo after' _ "$REPO_ROOT"
  [[ "$output" == *"→ LIVE_DIR not set"* ]]
  [[ "$output" == *"after"* ]]
}

@test "grade --all --exclude skips the named tasks; --exclude needs --all" {
  touch "$TEST_TMP/acme/acme-platform/marker.txt"
  printf 'g-09\t1\t2\ng-06\t1\t2\n' >"$LAB_HOME/progress"
  run "$LAB" grade --all --exclude g-09
  [ "$status" -eq 0 ]
  [[ "$output" == *"== g-06"* ]]
  [[ "$output" != *"== g-09"* ]]
  run "$LAB" grade --exclude g-09 g-06
  [ "$status" -eq 2 ]
  run "$LAB" grade --all --exclude
  [ "$status" -eq 2 ]
}

@test "grade --all tells its checks (LAB_GRADE_ALL=1) and refuses to nest" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  mkdir -p "$TEST_TMP/tracks/gradedemo/12-nested"
  printf -- '---\nid: g-12\ntitle: nested\ntarget_minutes: 5\nrequires: []\n---\n# nested\n' >"$TEST_TMP/tracks/gradedemo/12-nested/task.md"
  # shellcheck disable=SC2016
  printf '%s\n' 'check_code "inside grade --all" '"'"'[[ "${LAB_GRADE_ALL:-}" == 1 ]]'"'"' "not inside grade --all"' >"$TEST_TMP/tracks/gradedemo/12-nested/checks.sh"
  export TRACKS_DIR="$TEST_TMP/tracks"
  printf 'g-12\t1\t2\n' >"$LAB_HOME/progress"
  run "$LAB" grade g-12
  [ "$status" -eq 1 ]
  run "$LAB" grade --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ PASS  inside grade --all"* ]]
  LAB_GRADE_ALL=1 run "$LAB" grade --all
  [ "$status" -eq 2 ]
  [[ "$output" == *"already running"* ]]
}
