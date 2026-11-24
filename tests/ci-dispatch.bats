load test_helper

# tracks/terraform/lib/ci-dispatch.sh (tf-05's catchup): runs waiting for the prod environment's
# review on main get approved before catchup dispatches its own run, so they can't block it in
# the terraform-apply-prod concurrency group. Only the runs of the commit catchup's run applies
# (main's head): an older commit's waiting run is never approved.

setup() {
  setup_lab
  export STATE="$TEST_TMP/state" CI_POLL_SECONDS=0 CI_RETRY_SECONDS=0
  mkdir -p "$STATE" "$TEST_TMP/bin"
  # Two runs wait on main: 111 for main's head (aaa111), 110 for an older commit (bbb222).
  cat >"$TEST_TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE_LOG"
case "$*" in
  "run list -R o/r --workflow terraform.yml --branch main --status waiting --json databaseId,headSha --jq "*)
    runs='[]'
    [[ -f "$STATE/approved-111" ]] || runs='[{"databaseId":111,"headSha":"aaa111"}]'
    [[ -f "$STATE/approved-110" ]] || runs="$(jq -c '. + [{"databaseId":110,"headSha":"bbb222"}]' <<<"$runs")"
    jq -r "${@: -1}" <<<"$runs" ;;
  "api repos/o/r/commits/main --jq .sha") echo aaa111 ;;
  "api repos/o/r/actions/runs/111/pending_deployments --jq "* | "api repos/o/r/actions/runs/110/pending_deployments --jq "*) echo 7 ;;
  "api -X POST repos/o/r/actions/runs/"*"/pending_deployments -F environment_ids[]=7 -f state=approved -f comment="*)
    id=${4#repos/o/r/actions/runs/}; touch "$STATE/approved-${id%%/*}" ;;
  "run list -R o/r --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq .[].databaseId")
    [[ -f "$STATE/dispatched" ]] && echo 333
    echo 200 ;;
  "workflow run terraform.yml -R o/r --ref main -f stacks=all") touch "$STATE/dispatched" ;;
  "run view 333 -R o/r --json headSha --jq .headSha") echo aaa111 ;;
  "run view 333 -R o/r --json status,conclusion --jq "*) echo "completed success" ;;
  *) echo "unexpected: gh $*" >&2; exit 1 ;;
esac
SH
  chmod +x "$TEST_TMP/bin/gh"
  export PATH="$TEST_TMP/bin:$PATH"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/tracks/terraform/lib/ci-dispatch.sh"
}
teardown() { teardown_lab; }

@test "ci_approve_waiting approves the waiting runs of the given commit only (M2)" {
  run ci_approve_waiting o/r aaa111
  [ "$status" -eq 0 ]
  [[ "$output" == *"approved the pending deployment of run 111 (environment 7)"* ]]
  [ -f "$STATE/approved-111" ]
  [ ! -e "$STATE/approved-110" ]
  run ci_approve_waiting o/r ""
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/approved-110" ]
}

@test "ci_dispatch_wait approves main's waiting run before it dispatches, never an older commit's" {
  run ci_dispatch_wait o/r all tf-05
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tf-05: run 333 succeeded"* ]]
  approve=$(grep -n "POST repos/o/r/actions/runs/111/pending_deployments" "$FAKE_LOG" | head -n 1 | cut -d: -f1)
  dispatch=$(grep -n "workflow run terraform.yml" "$FAKE_LOG" | head -n 1 | cut -d: -f1)
  [ -n "$approve" ]
  [ -n "$dispatch" ]
  [ "$approve" -lt "$dispatch" ]
  run grep -c "POST repos/o/r/actions/runs/110/" "$FAKE_LOG"
  [ "$output" = 0 ]
}
