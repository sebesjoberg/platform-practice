# tf-17 checks (sourced by the grader; cwd = LIVE_DIR)

# Where the spoke module lives (terraform/modules/spoke, or $MODULES_DIR/spoke from tf-19), and
# the pipeline helpers shared with tf-18.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-module.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export TF17_WF=.github/workflows/terraform.yml TF17_REPO="$GH_OWNER/$LIVE_REPO"
export TF17_TEST_RE='terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+test'

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
export -f spoke_module_dir tf17_tests_plan_only ci_job ci_job_ids ci_plan_job ci_plan_independent ci_before_login ci_pr_green_or_caught_up

check_code "module tests mock azurerm and only plan" \
  'tf17_tests_plan_only "$(spoke_module_dir)"' \
  "the spoke module needs tests/*.tftest.hcl with mock_provider \"azurerm\" {} and at least two run blocks, each with command = plan"

check_code "a test proves that a bad input is rejected" \
  'd="$(spoke_module_dir)" && grep -qsE "^[[:space:]]*expect_failures[[:space:]]*=[[:space:]]*\[[[:space:]]*var\." "$d"/tests/*.tftest.hcl' \
  "add a run that passes an invalid input (such as address_space = \"10.1.0.0/24\") with expect_failures = [var.address_space]"

check_code "the plan job runs terraform test before azure/login, and plan still needs no other job" \
  'ci_plan_job "$TF17_WF" | ci_before_login "$TF17_TEST_RE" && ci_plan_independent "$TF17_WF"' \
  "add a step to the plan job, before azure/login, that runs terraform test for the module (init -backend=false first); no extra job: plan is the required check"

check "the latest pull request run of terraform.yml succeeded (or a newer catchup run on main)" \
  'ci_pr_green_or_caught_up "$TF17_REPO"' \
  "the newest completed pull_request run of terraform.yml in $TF17_REPO is not green: open it and read the terraform test step"
