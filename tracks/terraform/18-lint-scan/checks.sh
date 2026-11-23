# tf-18 checks (sourced by the grader; cwd = LIVE_DIR)

# Pipeline helpers shared with tf-17.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export TF18_WF=.github/workflows/terraform.yml TF18_REPO="$GH_OWNER/$LIVE_REPO"
# a tflint run other than tflint --init (those lines are dropped first)
export TF18_TFLINT_RE='(^|[[:space:]"])tflint([[:space:]]|$)'
export TF18_TRIVY_RE='trivy[^#]*[[:space:]]config[[:space:]]|scan-type:[[:space:]]*"?config'
export -f ci_job ci_plan_job ci_before_login ci_pr_green_or_caught_up

check_code ".tflint.hcl enables the azurerm ruleset" \
  '[[ -f .tflint.hcl ]] && grep -qE "source[[:space:]]*=[[:space:]]*\"github.com/terraform-linters/tflint-ruleset-azurerm\"" .tflint.hcl && grep -qE "^plugin[[:space:]]+\"azurerm\"" .tflint.hcl' \
  "commit .tflint.hcl at the repo root with plugin \"azurerm\" { enabled = true, version = \"0.29.0\", source = \"github.com/terraform-linters/tflint-ruleset-azurerm\" }"

check_code "the plan job runs tflint before azure/login" \
  'j="$(ci_plan_job "$TF18_WF")" && grep -qE "tflint[[:space:]]+--init" <<<"$j" && grep -vE "tflint[[:space:]]+--init" <<<"$j" | ci_before_login "$TF18_TFLINT_RE"' \
  "add tflint to the plan job, before azure/login: tflint --init, then tflint --recursive --config \"\$PWD/.tflint.hcl\" --chdir terraform"

check_code "the plan job runs trivy config before azure/login and fails on HIGH and CRITICAL findings" \
  'j="$(ci_plan_job "$TF18_WF")" && ci_before_login "$TF18_TRIVY_RE" <<<"$j" && grep -qE "(--exit-code[[:space:]=]+|exit-code:[[:space:]]*)[^0-9[:space:]]?1([^0-9]|$)" <<<"$j" && grep -qE "HIGH" <<<"$j" && grep -qE "CRITICAL" <<<"$j"' \
  "add trivy config to the plan job, before azure/login, with --exit-code 1 --severity HIGH,CRITICAL (trivy exits 0 on findings by default)"

check "the latest pull request run of terraform.yml succeeded (or a newer catchup run on main)" \
  'ci_pr_green_or_caught_up "$TF18_REPO"' \
  "the newest completed pull_request run of terraform.yml in $TF18_REPO is not green: read the tflint and trivy steps"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "repos/$TF18_REPO/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF18_REPO is not green (is the PR merged?)"
