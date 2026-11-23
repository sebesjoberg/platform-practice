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

# ci_run_planned <repo> <run id>: the run's plan job ran its Terraform work (a step about terraform,
# tflint or trivy succeeded). From tf-24 a PR that touches no Terraform path skips those steps and
# its plan job is green without testing anything.
ci_run_planned() {
  gh api "repos/$1/actions/runs/$2/jobs?per_page=100" --jq '[.jobs[] | select(.name == "plan") | .steps[]
    | select(.conclusion == "success" and (.name | test("^(Run|Post) ") | not) and (.name | test("terraform|tflint|trivy"; "i")))]
    | length > 0' | grep -qx true
}

# ci_pr_green_or_caught_up <owner/repo>: the plan job (tests, lint, scan) only runs on pull
# requests, so the newest completed pull_request run of terraform.yml that planned (see
# ci_run_planned) must be green. Catchup never opens a PR: it pushes "catchup: <id>" to main and
# dispatches a run. So it also passes when the newest completed run on main is green, newer than
# that PR run (or there is none), and its head commit message starts with "catchup:".
ci_pr_green_or_caught_up() {
  local runs="repos/$1/actions/workflows/terraform.yml/runs?status=completed&per_page=20" id concl created pr="" main
  while read -r id concl created; do
    [[ -n "$id" ]] || continue
    ci_run_planned "$1" "$id" || continue
    [[ "$concl" == success ]] && return 0
    pr=$created
    break
  done < <(gh api "$runs&event=pull_request" --jq '.workflow_runs[] | "\(.id) \(.conclusion) \(.created_at)"')
  main="$(gh api "$runs&branch=main" --jq '.workflow_runs[0] // {} | {conclusion, created_at, message: (.head_commit.message // "")}')" || return 1
  jq -e --arg pr "$pr" '.conclusion == "success" and (.message | startswith("catchup:"))
    and ($pr == "" or .created_at > $pr)' <<<"$main" >/dev/null
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

# From tf-24 a terraform.yml run on main whose push touched no Terraform path skips its apply
# jobs and is green without applying anything (an Ansible-only merge). Checks that want "the
# pipeline applies cleanly" must not count such runs. The helpers below need gh.

# ci_run_apply <repo> <run id>: prints the conclusion of the run's apply job (success, failure,
# skipped, ...), or "none" when the run has no job of that name.
ci_run_apply() {
  gh api "repos/$1/actions/runs/$2/jobs?per_page=100" --jq '[.jobs[] | select(.name == "apply")][0].conclusion // "none"'
}

# ci_main_green <repo>: the newest completed terraform.yml run on main that actually applied (or
# failed) succeeded. Green runs that skipped apply (no Terraform change) are passed over; a red
# run always counts. Looks at the 20 newest completed runs.
ci_main_green() {
  local id concl apply
  while read -r id concl; do
    [[ -n "$id" ]] || continue
    apply="$(ci_run_apply "$1" "$id")" || return 1
    if [[ "$apply" == skipped && "$concl" == success ]]; then continue; fi
    [[ "$concl" == success ]]
    return
  done < <(gh api "repos/$1/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=20" \
    --jq '.workflow_runs[] | "\(.id) \(.conclusion)"')
  return 1
}

# ci_applied_since <repo> <epoch>: a terraform.yml run created at or after <epoch> succeeded with
# its apply job run and green (a dispatched run, or a merge that changed Terraform).
ci_applied_since() {
  local iso id
  iso="$(date -u -d "@$2" +%Y-%m-%dT%H:%M:%SZ)"
  for id in $(gh api "repos/$1/actions/workflows/terraform.yml/runs?status=success&created=%3E%3D$iso&per_page=20" --jq '.workflow_runs[].id'); do
    [[ "$(ci_run_apply "$1" "$id")" == success ]] && return 0
  done
  return 1
}
