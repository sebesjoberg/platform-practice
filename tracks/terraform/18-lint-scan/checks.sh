# tf-18 checks (sourced by the grader; cwd = LIVE_DIR)

export TF18_WF=.github/workflows/terraform.yml TF18_REPO="$GH_OWNER/$LIVE_REPO"
# Prints the lines of job <job> under jobs: (awk -v job=plan).
export TF18_JOB_AWK='/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 } j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n; if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); cur = k } } j && cur == job { print }'
export TF18_RUNS='repos/'"$TF18_REPO"'/actions/workflows/terraform.yml/runs?status=completed&per_page=1'

tf18_plan_job() { [[ -f "$TF18_WF" ]] && awk -v job=plan "$TF18_JOB_AWK" "$TF18_WF"; }
export -f tf18_plan_job

check_code ".tflint.hcl enables the azurerm ruleset" \
  '[[ -f .tflint.hcl ]] && grep -qE "source[[:space:]]*=[[:space:]]*\"github.com/terraform-linters/tflint-ruleset-azurerm\"" .tflint.hcl && grep -qE "^plugin[[:space:]]+\"azurerm\"" .tflint.hcl' \
  "commit .tflint.hcl at the repo root with plugin \"azurerm\" { enabled = true, version = \"0.29.0\", source = \"github.com/terraform-linters/tflint-ruleset-azurerm\" }"

check_code "the plan job runs tflint" \
  'j="$(tf18_plan_job)" && grep -qE "tflint[[:space:]]+--init" <<<"$j" && grep -E "(^|[[:space:]\"])tflint[[:space:]]" <<<"$j" | grep -qvE "tflint[[:space:]]+--init"' \
  "add tflint to the plan job: tflint --init, then tflint --recursive --config \"\$PWD/.tflint.hcl\" --chdir terraform"

check_code "the plan job runs trivy config and fails on HIGH and CRITICAL findings" \
  'j="$(tf18_plan_job)" && grep -qE "trivy[^#]*[[:space:]]config[[:space:]]|scan-type:[[:space:]]*\"?config" <<<"$j" && grep -qE "(--exit-code[[:space:]=]+|exit-code:[[:space:]]*)[^0-9[:space:]]?1([^0-9]|$)" <<<"$j" && grep -qE "HIGH" <<<"$j" && grep -qE "CRITICAL" <<<"$j"' \
  "add trivy config to the plan job with --exit-code 1 --severity HIGH,CRITICAL (trivy exits 0 on findings by default)"

check "the latest pull request run of terraform.yml succeeded" \
  '[[ "$(gh api "$TF18_RUNS&event=pull_request" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed pull_request run of terraform.yml in $TF18_REPO is not green: read the tflint and trivy steps"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "$TF18_RUNS&branch=main" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF18_REPO is not green (is the PR merged?)"
