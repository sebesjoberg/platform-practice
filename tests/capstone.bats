load test_helper

# cap-01 (tracks/capstone/01-rebuild): the incident in setup.sh, and the live checks' helpers,
# against stand-in az/gh. Plus the docs follow-ups of Task 15.

CAP="$REPO_ROOT/tracks/capstone/01-rebuild"

setup() {
  setup_lab
  export STATE="$TEST_TMP/state" PREFIX=acme
  mkdir -p "$STATE" "$TEST_TMP/bin"
  # A stateful az for vm-acme-web-dev-2: present (old-id) until deleted; "rebuilt" brings a new
  # VM (new-id) that uses the same NIC.
  cat >"$TEST_TMP/bin/az" <<'SH'
#!/usr/bin/env bash
echo "az $*" >>"$FAKE_LOG"
case "$*" in
  "vm list -g rg-acme-dev --query "*)
    [[ -f "$STATE/no-rg" ]] && exit 3
    if [[ -f "$STATE/rebuilt" ]]; then printf 'new-id\t/disk/2\t/nic/1\n'
    elif [[ ! -f "$STATE/deleted" ]]; then printf 'old-id\t/disk/1\t/nic/1\n'; fi ;;
  "vm delete -g rg-acme-dev -n vm-acme-web-dev-2 --yes -o none") touch "$STATE/deleted" ;;
  "disk show --ids /disk/1 --query id -o tsv") [[ -f "$STATE/disk-gone" ]] && exit 3; echo /disk/1 ;;
  "disk delete --ids /disk/1 --yes -o none") touch "$STATE/disk-gone" ;;
  "network nic show --ids /nic/1 --query virtualMachine.id -o tsv")
    [[ -f "$STATE/nic-gone" && ! -f "$STATE/rebuilt" ]] && exit 3
    if [[ -f "$STATE/rebuilt" ]]; then echo /vm/new; else echo; fi ;;
  "network nic delete --ids /nic/1 -o none") touch "$STATE/nic-gone" ;;
  *) echo "unexpected: az $*" >&2; exit 1 ;;
esac
SH
  chmod +x "$TEST_TMP/bin/az"
  export PATH="$TEST_TMP/bin:$PATH"
}
teardown() { teardown_lab; }

snap() { cat "$LAB_HOME/snapshots/cap-01.ids"; }

@test "setup snapshots the VM, then deletes it, its OS disk and its NIC; prints only the symptom" {
  run bash "$CAP/setup.sh"
  [ "$status" -eq 0 ]
  [ -f "$STATE/deleted" ] && [ -f "$STATE/disk-gone" ] && [ -f "$STATE/nic-gone" ]
  grep -qx "vm_id=old-id" <(snap)
  grep -qx "os_disk=/disk/1" <(snap)
  grep -qx "nic=/nic/1" <(snap)
  grep -qE "^start=[0-9]+$" <(snap)
  [[ "$output" == *"vm-acme-web-dev-2 DOWN"* ]]
  [[ "$output" != *az* && "$output" != *Terraform* ]]
}

@test "setup again: nothing more to delete, the snapshot stays" {
  bash "$CAP/setup.sh" >/dev/null
  first="$(snap)"
  : >"$FAKE_LOG"
  run bash "$CAP/setup.sh"
  [ "$status" -eq 0 ]
  [ "$(snap)" = "$first" ]
  [[ "$(cat "$FAKE_LOG")" != *delete* ]]
}

@test "setup finishes an interrupted deletion" {
  mkdir -p "$LAB_HOME/snapshots"
  printf 'start=1\nvm_id=old-id\nos_disk=/disk/1\nnic=/nic/1\n' >"$LAB_HOME/snapshots/cap-01.ids"
  run bash "$CAP/setup.sh"
  [ "$status" -eq 0 ]
  [ -f "$STATE/deleted" ] && [ -f "$STATE/disk-gone" ] && [ -f "$STATE/nic-gone" ]
  grep -qx "start=1" <(snap)
}

@test "setup never touches a rebuilt VM (another vmId) or the NIC it reuses" {
  bash "$CAP/setup.sh" >/dev/null
  touch "$STATE/rebuilt"
  : >"$FAKE_LOG"
  run bash "$CAP/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *delete* ]]
}

@test "setup without the VM and without a snapshot fails (paused lab?)" {
  touch "$STATE/deleted"
  run bash "$CAP/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found in rg-acme-dev"* ]]
  [ ! -e "$LAB_HOME/snapshots/cap-01.ids" ]
}

@test "setup fails when the VMs can't be listed" {
  touch "$STATE/no-rg"
  run bash "$CAP/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot list the VMs in rg-acme-dev"* ]]
}

# load_checks: the cap-01 check helpers in this shell (check/check_code do nothing here).
load_checks() {
  export GH_OWNER=learner LIVE_REPO=acme-platform LIVE_DIR="$TEST_TMP/acme/acme-platform"
  check() { :; }
  check_code() { :; }
  # shellcheck disable=SC1091
  source "$CAP/checks.sh"
}

@test "checks: a triggered run counts only after the VM was created, and only with a green apply" {
  load_checks
  VM_CREATED="2026-11-23T10:00:00.1234567+00:00"
  RUN='{"id":7,"conclusion":"success","created_at":"2026-11-23T10:05:00Z","event":"workflow_run"}'
  JOB='{"name":"apply","conclusion":"success","labels":["self-hosted","acme-jump"]}'
  az() { echo "$VM_CREATED"; }
  gh() { case "$*" in *"/jobs"*) echo "$JOB" ;; *) echo "$RUN" ;; esac; }
  run cap01_triggered_run
  [ "$status" -eq 0 ]
  RUN='{"id":7,"conclusion":"success","created_at":"2026-11-23T09:59:59Z","event":"workflow_run"}'
  run cap01_triggered_run
  [ "$status" -ne 0 ]
  RUN='{"id":7,"conclusion":"failure","created_at":"2026-11-23T10:05:00Z","event":"workflow_run"}'
  run cap01_triggered_run
  [ "$status" -ne 0 ]
  RUN='{"id":7,"conclusion":"success","created_at":"2026-11-23T10:05:00Z","event":"workflow_run"}'
  JOB='{"name":"apply","conclusion":"skipped","labels":[]}'
  run cap01_triggered_run
  [ "$status" -ne 0 ]
  RUN='{"id":null,"conclusion":null,"created_at":null,"event":null}'
  run cap01_triggered_run
  [ "$status" -ne 0 ]
}

@test "checks: the VM must run and be a new one" {
  load_checks
  mkdir -p "$LAB_HOME/snapshots"
  printf 'start=1\nvm_id=old-id\n' >"$LAB_HOME/snapshots/cap-01.ids"
  az() { printf '%s\tVM running\n' "$VM"; }
  VM=new-id
  run cap01_vm_new
  [ "$status" -eq 0 ]
  VM=old-id
  run cap01_vm_new
  [ "$status" -ne 0 ]
  az() { printf 'new-id\tVM deallocated\n'; }
  run cap01_vm_new
  [ "$status" -ne 0 ]
}

@test "checks: keys compare without their comments; the VM needs a key besides the lab key" {
  load_checks
  [ "$(cap01_key_body "ssh-ed25519 AAAA gh-runner@vm")" = "ssh-ed25519 AAAA" ]
  gh() { echo "ssh-ed25519 LAB me"; }
  az() { printf 'ssh-ed25519 LAB me\nssh-ed25519 RUNNER gh-runner@jump\n'; }
  run cap01_vm_runner_login
  [ "$status" -eq 0 ]
  az() { printf 'ssh-ed25519 LAB other-comment\n'; }
  run cap01_vm_runner_login
  [ "$status" -ne 0 ]
}

@test "checks: the regression check never recurses inside grade --all" {
  load_checks
  fake_lab 1
  printf 'P\n' >"$TEST_TMP/results"
  GRADE_RESULTS="$TEST_TMP/results" LAB_ROOT="$TEST_TMP/lab" LAB_GRADE_ALL=1 run cap01_no_regressions
  [ "$status" -eq 0 ]
  [[ "$(cat "$FAKE_LOG")" != *lab.sh* ]]
}

# fake_lab <rc>: a lab.sh that logs its arguments, prints a regressions line and exits <rc>.
fake_lab() {
  mkdir -p "$TEST_TMP/lab"
  cat >"$TEST_TMP/lab/lab.sh" <<SH
#!/usr/bin/env bash
echo "lab.sh \$*" >>"\$FAKE_LOG"
echo "regressions: an-10"
exit $1
SH
  chmod +x "$TEST_TMP/lab/lab.sh"
}

@test "checks: grade --all runs only after every other cap-01 check passed, its output kept in a log" {
  load_checks
  fake_lab 1
  export LAB_ROOT="$TEST_TMP/lab" LAB_GRADE_ALL="" GRADE_RESULTS="$TEST_TMP/results"
  printf 'P\nF\nP\n' >"$GRADE_RESULTS"
  run cap01_no_regressions
  [ "$status" -eq 1 ]
  [[ "$(cat "$FAKE_LOG")" != *lab.sh* ]]
  : >"$GRADE_RESULTS"
  run cap01_no_regressions
  [ "$status" -eq 1 ]
  [[ "$(cat "$FAKE_LOG")" != *lab.sh* ]]
  printf 'P\nP\n' >"$GRADE_RESULTS"
  run cap01_no_regressions
  [ "$status" -eq 1 ]
  grep -qx "lab.sh grade --all --exclude cap-01" "$FAKE_LOG"
  [ "$(cat "$LAB_HOME/logs/cap-01-grade-all.log")" = "regressions: an-10" ]
  fake_lab 0
  run cap01_no_regressions
  [ "$status" -eq 0 ]
}

@test "checks: the regression reason names the log; the SSH checks get 180 s" {
  run grep -c 'cap01_grade_all_log) names them' "$CAP/checks.sh"
  [ "$output" -eq 1 ]
  t="$(grep -n '^GRADE_TIMEOUT=180' "$CAP/checks.sh" | cut -d: -f1)"
  c="$(grep -n "^check \"repo variable RUNNER_SSH_PUBLIC_KEY" "$CAP/checks.sh" | cut -d: -f1)"
  [ -n "$t" ] && [ -n "$c" ] && [ "$t" -lt "$c" ]
}

@test "docs: superseded handover bullets, stale live-verify lines and the old approval note are gone" {
  ! grep -qE "Certificates Officer|TCP 80" "$REPO_ROOT/tracks/terraform/25-vms-handover/task.md"
  ! grep -qiE "approve[^.]*apply-prod[^.]*ansible-only|ansible-only[^.]*approve" "$REPO_ROOT/tracks/ansible/README.md"
  ! grep -qE "ci_run_planned|gh variable get|az resource show --ids|tf-14 limitation" "$REPO_ROOT/docs/superpowers/live-verify.md"
  grep -qx "## Capstone (cap-01)" "$REPO_ROOT/docs/superpowers/live-verify.md"
  [ "$(wc -l <"$REPO_ROOT/README.md")" -lt 120 ]
}
