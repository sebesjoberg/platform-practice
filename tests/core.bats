load test_helper

setup() {
  setup_lab
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/tracks"
  # The repo may live under /mnt/ (WSL); don't treat the fakes as Windows builds.
  export WINDOWS_MOUNT_PREFIX="$TEST_TMP/no-windows/"
  LAB="$REPO_ROOT/lab.sh"
}
teardown() { teardown_lab; }

fake_azure() {
  fake_response az "account show --query {id:id,tenantId:tenantId} -o json" 0 \
    '{"id":"sub-123","tenantId":"ten-456"}'
  fake_response az "ad signed-in-user show --query id -o tsv" 0 "me-789"
  fake_response az "role assignment list --assignee me-789 --scope /subscriptions/sub-123 --query [?roleDefinitionName=='Owner'] -o json" 0 \
    '[{"roleDefinitionName":"Owner"}]'
  fake_response curl "-fsS https://api.ipify.org" 0 "198.51.100.7"
}

@test "rejects MSYS" {
  MSYSTEM=MINGW64 run "$LAB" status
  [ "$status" -eq 3 ]
  [[ "$output" == *"run the lab inside WSL/Linux"* ]]
}

@test "rejects windows az under /mnt" {
  mkdir -p "$TEST_TMP/no-windows"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/no-windows/az"
  chmod +x "$TEST_TMP/no-windows/az"
  PATH="$TEST_TMP/no-windows:$PATH" run "$LAB" init --prefix acme --gh-owner o --owner-tag t
  [ "$status" -eq 3 ]
  [[ "$output" == *"az is the Windows build; install the Linux one:"* ]]
}

@test "init writes config from fake az" {
  rm "$LAB_HOME/config.env"
  fake_azure
  run "$LAB" init --prefix demo --gh-owner octo --owner-tag sam --live-dir "$TEST_TMP/live"
  [ "$status" -eq 0 ]
  grep -qx 'PREFIX="demo"' "$LAB_HOME/config.env"
  grep -qx 'SUBSCRIPTION_ID="sub-123"' "$LAB_HOME/config.env"
  grep -qx 'TENANT_ID="ten-456"' "$LAB_HOME/config.env"
  grep -qx 'GH_OWNER="octo"' "$LAB_HOME/config.env"
  grep -qx 'OWNER_TAG="sam"' "$LAB_HOME/config.env"
  grep -qx 'LEARNER_IP="198.51.100.7"' "$LAB_HOME/config.env"
  grep -qx 'LIVE_REPO="demo-platform"' "$LAB_HOME/config.env"
  grep -qx "LIVE_DIR=\"$TEST_TMP/live\"" "$LAB_HOME/config.env"
  grep -qE '^SUFFIX="[a-z0-9]{6}"$' "$LAB_HOME/config.env"
  # re-init keeps the suffix
  s1=$(grep ^SUFFIX "$LAB_HOME/config.env")
  run "$LAB" init --prefix demo --gh-owner octo --owner-tag sam --live-dir "$TEST_TMP/live"
  [ "$status" -eq 0 ]
  [ "$s1" = "$(grep ^SUFFIX "$LAB_HOME/config.env")" ]
}

@test "init exits 3 without Owner role" {
  rm "$LAB_HOME/config.env"
  fake_azure
  fake_response az "role assignment list --assignee me-789 --scope /subscriptions/sub-123 --query [?roleDefinitionName=='Owner'] -o json" 0 '[]'
  run "$LAB" init --prefix demo --gh-owner octo --owner-tag sam
  [ "$status" -eq 3 ]
  [[ "$output" == *"Owner"* ]]
}

@test "init names the missing flag without a TTY" {
  rm "$LAB_HOME/config.env"
  fake_azure
  fake_response gh "api user --jq .login" 1
  run "$LAB" init --prefix demo --owner-tag sam </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--gh-owner"* ]]
}

@test "refresh-ip only changes LEARNER_IP" {
  fake_response curl "-fsS https://api.ipify.org" 0 "198.51.100.99"
  before=$(grep -v '^LEARNER_IP' "$LAB_HOME/config.env" | tr -d '"')
  run "$LAB" init --refresh-ip
  [ "$status" -eq 0 ]
  [[ "$output" == *"re-apply: shared (tf-25 NSG)"* ]]
  after=$(grep -v '^LEARNER_IP' "$LAB_HOME/config.env" | tr -d '"')
  [ "$before" = "$after" ]
  grep -qx 'LEARNER_IP="198.51.100.99"' "$LAB_HOME/config.env"
}

@test "task_ids orders by directory" {
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/tasks.sh"
  run task_ids demo
  [ "$output" = $'demo-01\ndemo-02' ]
  [ "$(task_meta demo-02 requires)" = "[demo-01]" ]
  [ "$(task_meta demo-01 target_minutes)" = "15" ]
  [[ "$(task_dir demo-02)" == */02-second ]]
}

@test "next starts first task and prints target" {
  run "$LAB" next demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Do the first thing."* ]]
  [[ "$output" == *"target: 15 min"* ]]
  [[ "$output" != *"target_minutes"* ]]
  cut -f1 "$LAB_HOME/progress" | grep -qx demo-01
  run "$LAB" task
  [[ "$output" == *"Do the first thing."* ]]
  run "$LAB" hint
  [[ "$output" == *"hint First"* ]]
  run "$LAB" solution demo-02
  [[ "$output" == *"solution Second"* ]]
}

@test "next refuses blocked task" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  sed -i 's/^requires: \[\]/requires: [demo-99]/' "$TEST_TMP/tracks/demo/01-first/task.md"
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" next demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"finish demo-99 first or ./lab.sh catchup demo-01"* ]]
}

@test "next moves on after finish and ends with all done" {
  run "$LAB" next demo
  source "$REPO_ROOT/lib/progress.sh"
  progress_finish demo-01
  run "$LAB" next
  [[ "$output" == *"Do the second thing."* ]]
  progress_finish demo-02
  run "$LAB" next demo
  [ "$status" -eq 0 ]
  [ "$output" = "all tasks in demo done" ]
}

@test "next runs setup.sh" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  printf '#!/usr/bin/env bash\ntouch "%s/setup-ran"\n' "$TEST_TMP" >"$TEST_TMP/tracks/demo/01-first/setup.sh"
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" next demo
  [ -f "$TEST_TMP/setup-ran" ]
}

@test "status shows done tasks" {
  run "$LAB" next demo
  source "$REPO_ROOT/lib/progress.sh"
  progress_finish demo-01
  run "$LAB" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo-01"*"First"*"done"* ]]
  [[ "$output" == *"demo-02"*"Second"*"-"* ]]
  [[ "$output" != *"demo-02"*"Second"*"done"* ]]
}

@test "later commands are stubs" {
  run "$LAB" pause
  [ "$status" -eq 2 ]
  [[ "$output" == *"not implemented yet"* ]]
}

@test "init rejects unsafe config values" {
  rm "$LAB_HOME/config.env"
  fake_azure
  run "$LAB" init --prefix demo --gh-owner octo --owner-tag 'Sam "S"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"OWNER_TAG"* ]]
  [ ! -e "$LAB_HOME/config.env" ]
  run "$LAB" init --prefix demo --gh-owner octo --owner-tag sam --live-dir '$(touch /tmp/pwned)'
  [ "$status" -ne 0 ]
  [ ! -e "$LAB_HOME/config.env" ]
}

@test "re-init with new prefix re-derives repos and dirs" {
  fake_azure
  "$LAB" init --prefix demo --gh-owner octo --owner-tag sam --live-dir "$TEST_TMP/a/demo-platform"
  s1=$(grep ^SUFFIX "$LAB_HOME/config.env")
  run "$LAB" init --prefix other --live-dir "$TEST_TMP/b/other-platform"
  [ "$status" -eq 0 ]
  [ "$s1" = "$(grep ^SUFFIX "$LAB_HOME/config.env")" ]
  grep -qx 'LIVE_REPO="other-platform"' "$LAB_HOME/config.env"
  grep -qx 'MODULES_REPO="other-terraform-modules"' "$LAB_HOME/config.env"
  grep -qx "MODULES_DIR=\"$TEST_TMP/b/other-terraform-modules\"" "$LAB_HOME/config.env"
}

@test "CRLF task.md is parsed" {
  mkdir -p "$TEST_TMP/crlf/demo/01-x"
  printf -- '---\r\nid: crlf-01\r\ntitle: Crlf\r\ntarget_minutes: 5\r\nrequires: []\r\n---\r\n# Body line\r\n' >"$TEST_TMP/crlf/demo/01-x/task.md"
  source "$REPO_ROOT/lib/common.sh"
  source "$REPO_ROOT/lib/tasks.sh"
  TRACKS_DIR="$TEST_TMP/crlf"
  [ "$(task_meta crlf-01 title)" = "Crlf" ]
  TRACKS_DIR="$TEST_TMP/crlf" run "$LAB" task crlf-01
  [[ "$output" == *"# Body line"* ]]
  [[ "$output" != *"title:"* ]]
}
