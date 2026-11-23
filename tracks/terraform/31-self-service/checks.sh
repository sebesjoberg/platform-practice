# tf-31 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

export TF31_LIVE="$GH_OWNER/$LIVE_REPO" TF31_MODS="$GH_OWNER/$MODULES_REPO" TF31_TEAM_REPO="$GH_OWNER/$PREFIX-payments-app"
export TF31_STACK=terraform/teams/payments TF31_RG="rg-$PREFIX-payments" TF31_ID="id-$PREFIX-payments-ci"
export TF31_SRC_RE="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//team-env\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+\""
export TF31_BUDGET_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-payments/providers/Microsoft.Consumption/budgets/budget-$PREFIX-payments?api-version=2021-10-01"
export TF31_TAGS_JQ='.location == env.LOCATION and .tags.owner == env.OWNER_TAG and (.tags.env // "") != "" and .tags.managed_by == "terraform"'
# CI's RBAC Administrator assignments: none at subscription scope may let it grant Contributor (or
# anything, without a condition); one on the team's group allows exactly Contributor to SPs.
export TF31_CONTRIB=b24988ac-6180-42a0-ab88-20f7382dd24c
export TF31_SUBRBAC_JQ='[.[] | select(.roleDefinitionName == "Role Based Access Control Administrator" and .scope == ("/subscriptions/" + env.SUBSCRIPTION_ID))
  | select((.condition // "") == "" or ((.condition // "") | ascii_downcase | contains(env.TF31_CONTRIB)))] | length == 0'
export TF31_RGRBAC_JQ='any(.[]; .roleDefinitionName == "Role Based Access Control Administrator" and (.scope | ascii_downcase) == (env.TF31_RG_ID | ascii_downcase)
  and ((.condition // "") | ascii_downcase | contains(env.TF31_CONTRIB)) and ((.condition // "") | test("PrincipalType\\][[:space:]]+StringEqualsIgnoreCase[[:space:]]+.ServicePrincipal")))'
export TF31_ROLES_JQ='(env.TF31_RG_ID | ascii_downcase) as $rg | length == 1 and .[0].roleDefinitionName == "Contributor" and (.[0].scope | ascii_downcase) == $rg'

# tf31_module_ok: team-env in the modules repo declares the team's resources inside a resource
# group it is given (the vended one), and creates no resource group itself.
tf31_module_ok() {
  local m="${MODULES_DIR:-}/team-env" r
  [[ -d "$m" ]] || return 1
  for r in azurerm_user_assigned_identity azurerm_federated_identity_credential \
    azurerm_role_assignment azurerm_consumption_budget_resource_group; do
    grep -qsE "^resource[[:space:]]+\"$r\"" "$m"/*.tf || return 1
  done
  grep -qsE '^variable[[:space:]]+"resource_group_(name|id)"' "$m"/*.tf &&
    ! grep -qsE '^resource[[:space:]]+"azurerm_resource_group"' "$m"/*.tf &&
    grep -qsF 'Contributor' "$m"/*.tf && grep -qsF 'refs/heads/main' "$m"/*.tf
}
# tf31_vended: bootstrap creates the payments group and gives CI an RBAC Administrator assignment
# scoped to a resource group it declares, limited to Contributor for service principals.
tf31_vended() {
  local b
  b="$(cat terraform/bootstrap/*.tf 2>/dev/null)" || return 1
  [[ "$(grep -cE '^resource[[:space:]]+"azurerm_resource_group"' <<<"$b")" -ge 2 ]] &&
    grep -qF payments <<<"$b" &&
    grep -qE '^[[:space:]]*scope[[:space:]]*=[[:space:]]*azurerm_resource_group\.' <<<"$b" &&
    grep -qF "$TF31_CONTRIB" <<<"$b" &&
    grep -qE 'roleAssignments:PrincipalType\][[:space:]]+StringEqualsIgnoreCase[[:space:]]+.ServicePrincipal' <<<"$b"
}
# tf31_stack_ok: the payments stack has its own state key and exactly one module call,
# team_payments, from team-env at a release tag with a budget of 100, and no resources of its own.
tf31_stack_ok() {
  local d=$TF31_STACK
  grep -rqsE 'backend[[:space:]]+"azurerm"' "$d" --include='*.tf' &&
    grep -rqsE 'key[[:space:]]*=[[:space:]]*"teams-payments\.tfstate"' "$d" --include='*.tf' &&
    [[ "$(cat "$d"/*.tf | grep -cE '^[[:space:]]*module[[:space:]]+"')" -eq 1 ]] &&
    grep -qsE '^[[:space:]]*module[[:space:]]+"team_payments"' "$d"/*.tf &&
    grep -qsE "$TF31_SRC_RE" "$d"/*.tf &&
    grep -qsE '^[[:space:]]*resource_group_name[[:space:]]*=' "$d"/*.tf &&
    grep -qsE '^[[:space:]]*budget_amount[[:space:]]*=[[:space:]]*100([^0-9]|$)' "$d"/*.tf &&
    ! grep -qsE '^[[:space:]]*resource[[:space:]]+"' "$d"/*.tf
}
# tf31_subject: the OIDC subject the team repo's main branch gets (immutable format).
tf31_subject() {
  local p
  p="$(gh api "repos/$TF31_TEAM_REPO/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null || true)"
  [[ "$p" == *@* ]] || p="$(gh api "repos/$TF31_TEAM_REPO" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"')"
  printf '%s:ref:refs/heads/main\n' "$p"
}
export -f tf31_module_ok tf31_vended tf31_stack_ok tf31_subject

check_code "team-env in the modules repo: identity, federated credential, Contributor, budget, in a given group" \
  'tf31_module_ok' \
  "$MODULES_REPO/team-env takes the vended group (variable resource_group_name) and creates no resource group; it needs azurerm_user_assigned_identity, azurerm_federated_identity_credential (main branch), an azurerm_role_assignment with Contributor and azurerm_consumption_budget_resource_group"

check_code "the starter's TODO(tf-31) blocks in team-env/main.tf are done" \
  '[[ -d "${MODULES_DIR:-}/team-env" ]] && ! grep -qsF "TODO(tf-31)" "$MODULES_DIR"/team-env/*.tf' \
  "fill in every TODO(tf-31) block of $MODULES_REPO/team-env/main.tf"

check_code "terraform/teams/payments: own state key, one module \"team_payments\" call, budget 100" \
  'tf31_stack_ok' \
  "terraform/teams/payments needs backend key teams-payments.tfstate and exactly one module \"team_payments\" (source team-env?ref=vX.Y.Z, resource_group_name of the vended group, budget_amount = 100), no resources of its own"

check_code "CHANGELOG.md has a 3.1.0 entry for team-env" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && [[ -f "$c" ]] && grep -qE "^#+[^0-9]*v?3\.1\.0" "$c" && grep -qF team-env "$c"' \
  "add a \"## 3.1.0\" entry for the new team-env module to $MODULES_REPO/CHANGELOG.md"

check_code "bootstrap vends the payments group and lets CI grant Contributor there only" \
  'tf31_vended' \
  "terraform/bootstrap must create rg-$PREFIX-payments and give CI Role Based Access Control Administrator with scope = that group, condition: only Contributor (b24988ac-...) for PrincipalType ServicePrincipal (the starter's team-vending.tf)"

check "the team repo $TF31_TEAM_REPO exists and is public" \
  '[[ "$(gh api "repos/$TF31_TEAM_REPO" --jq .visibility)" == public ]]' \
  "gh repo create $TF31_TEAM_REPO --public"

check "$TF31_RG exists with the required tags" \
  'az group show -n "$TF31_RG" -o json | jq -e "$TF31_TAGS_JQ"' \
  "expected $TF31_RG in $LOCATION with tags owner=$OWNER_TAG, env and managed_by=terraform (merged and applied?)"

check "CI can't grant Contributor at subscription scope" \
  'pid="$(az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query principalId -o tsv)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --scope "/subscriptions/$SUBSCRIPTION_ID" -o json | jq -e "$TF31_SUBRBAC_JQ"' \
  "id-$PREFIX-github-ci holds Role Based Access Control Administrator on the subscription with Contributor in its condition (or no condition): team grants belong on the team's group only; remove it from bootstrap and apply"

check "CI may grant Contributor to service principals in $TF31_RG" \
  'pid="$(az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query principalId -o tsv)" && [[ -n "$pid" ]] && TF31_RG_ID="$(az group show -n "$TF31_RG" --query id -o tsv)" && export TF31_RG_ID && az role assignment list --assignee "$pid" --scope "$TF31_RG_ID" -o json | jq -e "$TF31_RGRBAC_JQ"' \
  "expected Role Based Access Control Administrator for id-$PREFIX-github-ci on $TF31_RG with a condition allowing only Contributor for ServicePrincipal (bootstrap's team vending, applied locally)"

check "$TF31_ID trusts only the team repo's main branch" \
  's="$(tf31_subject)" && az identity federated-credential list -g "$TF31_RG" --identity-name "$TF31_ID" -o json | jq -e --arg s "$s" "length >= 1 and all(.[]; .subject == \$s and .issuer == \"https://token.actions.githubusercontent.com\")"' \
  "$TF31_ID needs federated credentials only for <immutable prefix of $TF31_TEAM_REPO>:ref:refs/heads/main"

check "$TF31_ID is Contributor on $TF31_RG and nothing else" \
  'pid="$(az identity show -g "$TF31_RG" -n "$TF31_ID" --query principalId -o tsv)" && [[ -n "$pid" ]] && TF31_RG_ID="$(az group show -n "$TF31_RG" --query id -o tsv)" && export TF31_RG_ID && az role assignment list --assignee "$pid" --all -o json | jq -e "$TF31_ROLES_JQ"' \
  "$TF31_ID must hold exactly one role assignment: Contributor on $TF31_RG"

check "budget-$PREFIX-payments: 100 a month on $TF31_RG" \
  'az rest --method get --url "$TF31_BUDGET_URL" -o json | jq -e ".properties.amount == 100 and .properties.timeGrain == \"Monthly\" and (.properties.notifications | length) >= 1"' \
  "expected budget budget-$PREFIX-payments on $TF31_RG, amount 100, Monthly, with alerts"

check "tag v3.1.0 exists in $TF31_MODS and holds team-env" \
  'gh api "repos/$TF31_MODS/contents/team-env?ref=v3.1.0" --jq ".[].name" | grep -c "\.tf$" >/dev/null' \
  "tag the release and push it: git tag -a v3.1.0 -m \"v3.1.0: team-env\" && git push origin v3.1.0"

check "latest completed terraform run on main succeeded" \
  'ci_main_green "$TF31_LIVE"' \
  "the newest completed terraform.yml run on main is not green; open it in the Actions tab"
