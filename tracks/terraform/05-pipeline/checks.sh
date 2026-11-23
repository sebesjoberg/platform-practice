# tf-05 checks (sourced by the grader; cwd = LIVE_DIR)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

export TF05_WF=.github/workflows/terraform.yml TF05_REPO="$GH_OWNER/$LIVE_REPO"
export TF05_TAGS_JQ='.location == env.LOCATION and .tags.owner == env.OWNER_TAG and .tags.env == "hub" and .tags.managed_by == "terraform"'
export TF05_VARS_JQ='(map({(.name): .value}) | add // {}) as $v | $v.AZURE_SUBSCRIPTION_ID == env.SUBSCRIPTION_ID and $v.AZURE_TENANT_ID == env.TENANT_ID and $v.AZURE_CLIENT_ID == env.TF05_CLIENT_ID'
export TF05_TODO_RE='^[[:space:]]*# TODO\(tf-05\)'
export TF05_HIDDEN_RE='echo[[:space:]]+"?list=\$\('
export TF05_COMMENT_JQ='.[] | select(.user.login == "github-actions[bot]" and ((.body // "") | contains("Terraform plan"))) | .id'
# Job helpers shared with tf-17, tf-18 and tf-24 (ci_plan_independent: plan and apply exist,
# plan has no needs:).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_job ci_job_ids ci_plan_independent

check_code "landing-zone stack has its own state key" \
  'grep --exclude-dir=.terraform -rqsE "backend[[:space:]]+\"azurerm\"" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "key[[:space:]]*=[[:space:]]*\"landing-zone\.tfstate\"" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "use_azuread_auth[[:space:]]*=[[:space:]]*true" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone needs backend \"azurerm\" with key = \"landing-zone.tfstate\" and use_azuread_auth = true"

check_code "landing-zone declares a resource group" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_resource_group\"" terraform/landing-zone --include="*.tf"' \
  "no azurerm_resource_group in terraform/landing-zone"

check_code "workflow has push, pull_request and workflow_dispatch with input stacks" \
  '[[ -f "$TF05_WF" ]] && grep -qE "^[[:space:]]*pull_request:" "$TF05_WF" && grep -qE "^[[:space:]]*push:" "$TF05_WF" && grep -qE "^[[:space:]]*workflow_dispatch:" "$TF05_WF" && grep -qE "^[[:space:]]+stacks:" "$TF05_WF"' \
  "$TF05_WF must trigger on pull_request, push and workflow_dispatch (input stacks)"

check_code "workflow has the jobs plan and apply, and plan needs no other job" \
  'ci_plan_independent "$TF05_WF"' \
  "$TF05_WF needs the jobs plan and apply, and plan must not have needs: (a job it waits for could fail and leave the required plan check skipped)"

check_code "stack discovery finds landing-zone and skips bootstrap" \
  '[[ -f .github/scripts/stacks.sh ]] && out="$(bash .github/scripts/stacks.sh all)" && [[ " $out " == *" landing-zone "* && " $out " != *" bootstrap "* ]]' \
  ".github/scripts/stacks.sh all must list landing-zone and never bootstrap"

check_code "the starter's TODO(tf-05) parts are done" \
  '[[ -f "$TF05_WF" ]] && ! grep -qE "$TF05_TODO_RE" "$TF05_WF"' \
  "$TF05_WF still contains # TODO(tf-05) marker lines"

check_code "stack discovery errors are not hidden behind echo" \
  '[[ -f "$TF05_WF" ]] && ! grep -qE "$TF05_HIDDEN_RE" "$TF05_WF"' \
  "run stacks.sh on its own line (list=\"\$(bash .github/scripts/stacks.sh ...)\"), not inside echo \"list=\$(...)\": echo returns 0 and hides failures"

check_code "workflow logs in with OIDC and holds no client secret" \
  '[[ -f "$TF05_WF" ]] && grep -qE "id-token:[[:space:]]*write" "$TF05_WF" && grep -qE "azure/login@v2" "$TF05_WF" && grep -qE "ARM_USE_OIDC:[[:space:]]*\"?true" "$TF05_WF" && ! grep -qiE "client-secret|CLIENT_SECRET|creds:" "$TF05_WF"' \
  "$TF05_WF needs id-token: write, azure/login@v2 and ARM_USE_OIDC: true, and no client secret"

check "workflow terraform.yml is active on GitHub" \
  '[[ "$(gh api "repos/$TF05_REPO/actions/workflows/terraform.yml" --jq .state)" == active ]]' \
  "no active workflow terraform.yml in $TF05_REPO (is it merged to main?)"

check "latest completed terraform run on main succeeded" \
  'ci_main_green "$TF05_REPO"' \
  "the newest completed terraform.yml run on main is not green; open it in the Actions tab"

# grep -c reads all of the paginated output (grep -q could close the pipe early under pipefail).
check "a PR has a plan comment from the pipeline" \
  'gh api --paginate "repos/$TF05_REPO/issues/comments?per_page=100" --jq "$TF05_COMMENT_JQ" | grep -c . >/dev/null' \
  "no PR comment containing \"Terraform plan\" from github-actions[bot]"

check "repo variables AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID are right" \
  'TF05_CLIENT_ID="$(az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query clientId -o tsv)" && [[ -n "$TF05_CLIENT_ID" ]] && export TF05_CLIENT_ID && gh api "repos/$TF05_REPO/actions/variables?per_page=100" --jq ".variables" | jq -e "$TF05_VARS_JQ"' \
  "repo variables must hold the client ID of id-$PREFIX-github-ci, tenant $TENANT_ID and subscription $SUBSCRIPTION_ID"

check "no ARM_* or AZURE_CLIENT_SECRET repo secrets" \
  's="$(gh api "repos/$TF05_REPO/actions/secrets?per_page=100" --jq ".secrets[].name")" && ! grep -qE "^(ARM_.*|AZURE_CLIENT_SECRET)$" <<<"$s"' \
  "delete repo secrets named ARM_* / AZURE_CLIENT_SECRET; OIDC needs none"

check "rg-$PREFIX-hub exists in $LOCATION with the required tags" \
  'az group show -n "rg-$PREFIX-hub" -o json | jq -e "$TF05_TAGS_JQ"' \
  "expected rg-$PREFIX-hub in $LOCATION with tags owner=$OWNER_TAG, env=hub, managed_by=terraform (applied by the pipeline)"
