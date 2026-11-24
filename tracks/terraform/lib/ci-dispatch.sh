# shellcheck shell=bash
# Run the live repo's terraform workflow from catchup and wait for it. Sourced by tf-05's
# catchup.sh. Needs gh. From tf-24 a run may hold its apply-prod job for the prod environment's
# required reviewer; catchup was confirmed by the learner, who is that reviewer, so it approves
# the pending deployment as them. Poll intervals are overridable for tests (CI_POLL_SECONDS,
# CI_RETRY_SECONDS).

# ci_new_run <repo> <known ids> [workflow file]: the newest workflow_dispatch run of the workflow
# (default terraform.yml) whose id is not in <known ids> (space separated, with spaces around),
# empty if none yet.
ci_new_run() {
  local r
  for r in $(gh run list -R "$1" --workflow "${3:-terraform.yml}" --event workflow_dispatch --limit 20 --json databaseId --jq '.[].databaseId'); do
    if [[ "$2" != *" $r "* ]]; then
      echo "$r"
      return 0
    fi
  done
}

# ci_approve_pending <repo> <run id>: approve every deployment of the run that waits for the
# current user's review.
ci_approve_pending() {
  local eid
  for eid in $(gh api "repos/$1/actions/runs/$2/pending_deployments" --jq '.[] | select(.current_user_can_approve) | .environment.id'); do
    gh api -X POST "repos/$1/actions/runs/$2/pending_deployments" -F "environment_ids[]=$eid" \
      -f state=approved -f comment="approved by ./lab.sh catchup" >/dev/null &&
      echo "approved the pending deployment of run $2 (environment $eid)"
  done
}

# ci_approve_waiting <repo> <head sha>: approve the pending deployments of the terraform.yml runs on
# main for commit <head sha> that wait for a review. Catchup's own push to main starts a run whose
# apply-prod job waits in the concurrency group terraform-apply-prod; left alone, it would hold up
# the apply-prod job of the run catchup dispatches, which then never finishes. Catchup was
# confirmed by the learner, who is the reviewer, and such a run applies the tree catchup pushed
# (the commit the dispatched run applies), so approving it is the simplest correct option
# (cancelling would also work, but leaves red runs on main). A waiting run for any other commit
# (an older merge) is never approved: it would apply an old tree to prod. No sha: nothing.
ci_approve_waiting() {
  local r
  [[ "$2" =~ ^[0-9a-f]+$ ]] || return 0
  for r in $(gh run list -R "$1" --workflow terraform.yml --branch main --status waiting --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$2\") | .databaseId"); do
    ci_approve_pending "$1" "$r" || true
  done
}

# ci_wait_run <repo> <run id>: wait until the run completes (at most 90 minutes), approving
# pending deployments on the way: its own and those of any other waiting run on main for the same
# commit, which could block it through the concurrency group. 0 = success.
ci_wait_run() {
  local repo=$1 id=$2 state sha deadline=$((SECONDS + 5400))
  sha="$(gh run view "$id" -R "$repo" --json headSha --jq .headSha)" || sha=""
  while ((SECONDS < deadline)); do
    state="$(gh run view "$id" -R "$repo" --json status,conclusion --jq '.status + " " + (.conclusion // "")')" || state="unknown"
    case "$state" in
      "completed success") return 0 ;;
      completed*) return 1 ;;
      waiting*) ci_approve_pending "$repo" "$id" || true ;;
    esac
    ci_approve_waiting "$repo" "$sha" || true
    sleep "${CI_POLL_SECONDS:-15}"
  done
  echo "run $id did not finish within 90 minutes" >&2
  return 1
}

# ci_dispatch_wait <repo> <stacks> <tag>: dispatch terraform.yml on main with -f stacks=<stacks>
# and wait for that run; up to 3 attempts (fresh role assignments can take minutes). <tag>
# prefixes the messages.
ci_dispatch_wait() {
  local repo=$1 stacks=$2 tag=$3 attempt known id sha
  for attempt in 1 2 3; do
    # the dispatched run applies main's head: approve only that commit's waiting runs
    sha="$(gh api "repos/$repo/commits/main" --jq .sha)" || sha=""
    ci_approve_waiting "$repo" "$sha" || true
    known=" $(gh run list -R "$repo" --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq '.[].databaseId' | tr '\n' ' ') "
    gh workflow run terraform.yml -R "$repo" --ref main -f stacks="$stacks"
    id=""
    for _ in $(seq 1 30); do
      id="$(ci_new_run "$repo" "$known")"
      [[ -n "$id" ]] && break
      sleep "${CI_POLL_SECONDS:-5}"
    done
    [[ -n "$id" ]] || { echo "$tag: could not find the dispatched run" >&2; return 1; }
    echo "$tag: waiting for run $id (stacks: $stacks)"
    if ci_wait_run "$repo" "$id"; then
      echo "$tag: run $id succeeded"
      return 0
    fi
    echo "$tag: run $id failed (attempt $attempt/3), retrying in 60s" >&2
    sleep "${CI_RETRY_SECONDS:-60}"
  done
  echo "$tag: the terraform workflow keeps failing; see gh run list -R $repo" >&2
  return 1
}

# ci_workflow_wait <repo> <workflow file> <tag>: dispatch another workflow of the live repo on
# main (no inputs; tf-27's drift.yml) and wait for that run. One attempt: 0 = success.
ci_workflow_wait() {
  local repo=$1 wf=$2 tag=$3 known id
  known=" $(gh run list -R "$repo" --workflow "$wf" --event workflow_dispatch --limit 20 --json databaseId --jq '.[].databaseId' | tr '\n' ' ') "
  gh workflow run "$wf" -R "$repo" --ref main
  id=""
  for _ in $(seq 1 30); do
    id="$(ci_new_run "$repo" "$known" "$wf")"
    [[ -n "$id" ]] && break
    sleep "${CI_POLL_SECONDS:-5}"
  done
  [[ -n "$id" ]] || { echo "$tag: could not find the dispatched $wf run" >&2; return 1; }
  echo "$tag: waiting for $wf run $id"
  if ci_wait_run "$repo" "$id"; then
    echo "$tag: $wf run $id succeeded"
    return 0
  fi
  echo "$tag: $wf run $id failed; see gh run view $id -R $repo --log-failed" >&2
  return 1
}
