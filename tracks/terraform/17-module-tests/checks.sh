# tf-17 checks (sourced by the grader; cwd = LIVE_DIR)

# Where the spoke module lives (terraform/modules/spoke, or $MODULES_DIR/spoke from tf-19).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-module.sh"
export TF17_WF=.github/workflows/terraform.yml TF17_REPO="$GH_OWNER/$LIVE_REPO"
# Prints the lines of one job (default plan) under jobs:, and sets nothing else.
export TF17_JOB_AWK='/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 } j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n; if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); cur = k } } j && cur == job { print }'
export TF17_JOBS_AWK='/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 } j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n; if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); print k } }'

# tf17_tests_plan_only <dir>: tests/*.tftest.hcl exist; each mocks azurerm and every run block
# in it says command = plan; at least two runs in all.
tf17_tests_plan_only() {
  local d=$1 f runs total=0
  compgen -G "$d/tests/*.tftest.hcl" >/dev/null || return 1
  for f in "$d"/tests/*.tftest.hcl; do
    grep -qE '^[[:space:]]*mock_provider[[:space:]]+"azurerm"' "$f" || return 1
    runs="$(grep -cE '^run[[:space:]]+"' "$f" || true)"
    [[ "$runs" -eq "$(grep -cE '^[[:space:]]+command[[:space:]]*=[[:space:]]*plan[[:space:]]*$' "$f" || true)" ]] || return 1
    total=$((total + runs))
  done
  [[ $total -ge 2 ]]
}
export -f spoke_module_dir tf17_tests_plan_only

check_code "module tests mock azurerm and only plan" \
  'tf17_tests_plan_only "$(spoke_module_dir)"' \
  "the spoke module needs tests/*.tftest.hcl with mock_provider \"azurerm\" {} and at least two run blocks, each with command = plan"

check_code "a test proves that a bad input is rejected" \
  'd="$(spoke_module_dir)" && grep -qsE "^[[:space:]]*expect_failures[[:space:]]*=[[:space:]]*\[[[:space:]]*var\." "$d"/tests/*.tftest.hcl' \
  "add a run that passes an invalid input (such as address_space = \"10.1.0.0/24\") with expect_failures = [var.address_space]"

check_code "the plan job runs terraform test, and the workflow still has only plan and apply" \
  '[[ -f "$TF17_WF" ]] && awk -v job=plan "$TF17_JOB_AWK" "$TF17_WF" | grep -qE "terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+test" && [[ "$(awk "$TF17_JOBS_AWK" "$TF17_WF" | sort | tr -s "[:space:]" " ")" == "apply plan " ]]' \
  "add a step to the plan job that runs terraform test for the module (init -backend=false first); no extra job: plan is the required check"

check "the latest pull request run of terraform.yml succeeded" \
  '[[ "$(gh api "repos/$TF17_REPO/actions/workflows/terraform.yml/runs?event=pull_request&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed pull_request run of terraform.yml in $TF17_REPO is not green: open it and read the terraform test step"
