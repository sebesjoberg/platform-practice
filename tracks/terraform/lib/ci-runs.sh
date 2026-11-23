# shellcheck shell=bash
# Pipeline checks shared by tf-05, tf-17, tf-18 and tf-24 (sourced by checks.sh; needs gh and jq for the live
# one). checks.sh exports what its commands use with export -f.

# ci_job <workflow file> <job id>: prints the lines of that job (from "  <job>:" to the next job
# at the same indent under jobs:). Used by tf-05, tf-17, tf-18 and tf-24.
ci_job() {
  [[ -f "$1" ]] || return 1
  awk -v want="$2" '/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 }
    j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n
      if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); cur = k } }
    j && cur == want { print }' "$1"
}

# ci_plan_job <workflow file>: prints the lines of the plan job.
ci_plan_job() { ci_job "$1" plan; }

# ci_job_ids <workflow file>: the job ids directly under jobs:, one per line.
ci_job_ids() {
  [[ -f "$1" ]] || return 1
  awk '/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 }
    j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n
      if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); print k } }' "$1"
}

# ci_before_login <ERE> (plan job on stdin): a non-comment line matching <ERE> exists and comes
# before the azure/login step, so third-party tooling never runs with an authenticated session.
ci_before_login() {
  awk -v re="$1" '/^[[:space:]]*#/ { next }
    !hit && $0 ~ re { hit = NR }
    !login && /azure\/login@/ { login = NR }
    END { exit !(hit && (!login || hit < login)) }'
}

# ci_pr_green_or_caught_up <owner/repo>: the plan job (tests, lint, scan) only runs on pull
# requests, so the newest completed pull_request run of terraform.yml must be green. Catchup never
# opens a PR: it pushes "catchup: <id>" to main and dispatches a run. So it also passes when the
# newest completed run on main is green, newer than that PR run (or there is none), and its head
# commit message starts with "catchup:".
ci_pr_green_or_caught_up() {
  local runs="repos/$1/actions/workflows/terraform.yml/runs?status=completed&per_page=1" pr main
  pr="$(gh api "$runs&event=pull_request" --jq '.workflow_runs[0] // {} | {conclusion, created_at}')" || return 1
  [[ "$(jq -r '.conclusion // ""' <<<"$pr")" == success ]] && return 0
  main="$(gh api "$runs&branch=main" --jq '.workflow_runs[0] // {} | {conclusion, created_at, message: (.head_commit.message // "")}')" || return 1
  jq -e --argjson pr "$pr" '.conclusion == "success" and (.message | startswith("catchup:"))
    and ($pr.created_at == null or .created_at > $pr.created_at)' <<<"$main" >/dev/null
}

# ci_plan_independent <workflow file>: the jobs plan and apply exist and plan has no needs:. plan
# is the required status check (tf-06); a job it waited for could fail and leave it skipped,
# and a skipped required check counts as passed. More jobs are fine (tf-24 adds apply-prod).
ci_plan_independent() {
  local ids
  ids="$(ci_job_ids "$1")" || return 1
  grep -qx plan <<<"$ids" && grep -qx apply <<<"$ids" &&
    ! ci_job "$1" plan | grep -qE '^[[:space:]]+needs:'
}
