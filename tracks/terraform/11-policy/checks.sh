# tf-11 checks (sourced by the grader; cwd = LIVE_DIR)

export TF11_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
export TF11_PROBE="rg-$PREFIX-policytest"
export TF11_RPC_JQ='any(.[]; .roleDefinitionName == "Resource Policy Contributor" and .scope == env.TF11_SCOPE)'
export TF11_DEF_JQ='.policyType == "Custom" and (.mode | ascii_downcase) == "all" and (.policyRule.then.effect | ascii_downcase) == "deny"'
export TF11_TAG_ASSIGN_JQ='(.policyDefinitionId | ascii_downcase) == ((env.TF11_SCOPE + "/providers/Microsoft.Authorization/policyDefinitions/" + env.PREFIX + "-require-owner-tag") | ascii_downcase)'
export TF11_LOC_ASSIGN_JQ='(.policyDefinitionId | ascii_downcase | endswith("/policydefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c")) and .parameters.listOfAllowedLocations.value == ["swedencentral"]'
# The probe: an untagged rg-* group must be refused by policy. Whatever happens, the group must
# not survive: delete a leftover first, and delete it again if the create got through.
tf11_probe() {
  local out rc
  if [[ "$(az group exists -n "$TF11_PROBE")" == true ]]; then
    az group delete -n "$TF11_PROBE" --yes >/dev/null 2>&1 || true # leftover: wait, it's empty
  fi
  out="$(az group create -n "$TF11_PROBE" -l "$LOCATION" -o none 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    az group delete -n "$TF11_PROBE" --yes --no-wait >/dev/null 2>&1 || true
    return 1
  fi
  grep -q RequestDisallowedByPolicy <<<"$out"
}
tf11_pid() { az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query principalId -o tsv; }
export -f tf11_probe tf11_pid

check_code "bootstrap gives the CI identity Resource Policy Contributor" \
  'grep -rqsE "Resource Policy Contributor|36243c78-bf99-498c-9df9-86d9f8d28608" terraform/bootstrap --include="*.tf"' \
  "terraform/bootstrap needs an azurerm_role_assignment of Resource Policy Contributor for the CI identity"

check_code "landing-zone declares a custom policy definition and subscription assignments" \
  'grep -rqsE "resource[[:space:]]+\"azurerm_policy_definition\"" terraform/landing-zone --include="*.tf" && grep -rqsE "resource[[:space:]]+\"azurerm_subscription_policy_assignment\"" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone needs azurerm_policy_definition and azurerm_subscription_policy_assignment resources"

check_code "landing-zone assigns the built-in Allowed locations" \
  'grep -rqsE "e56962a6-4747-49cd-b67b-bf8b01975c4c|\"Allowed locations\"" terraform/landing-zone --include="*.tf" && grep -rqsF "listOfAllowedLocations" terraform/landing-zone --include="*.tf"' \
  "assign the built-in Allowed locations (e56962a6-4747-49cd-b67b-bf8b01975c4c) with the parameter listOfAllowedLocations"

check "CI identity holds Resource Policy Contributor on the subscription" \
  'pid="$(tf11_pid)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --all -o json | jq -e "$TF11_RPC_JQ"' \
  "id-$PREFIX-github-ci needs Resource Policy Contributor at $TF11_SCOPE (apply terraform/bootstrap locally)"

check "policy definition $PREFIX-require-owner-tag is custom, mode All, effect deny" \
  'az policy definition show -n "$PREFIX-require-owner-tag" -o json | jq -e "$TF11_DEF_JQ"' \
  "expected a custom policy definition $PREFIX-require-owner-tag with mode All and then.effect deny"

check "assignment $PREFIX-require-owner-tag uses that definition on the subscription" \
  'az policy assignment show -n "$PREFIX-require-owner-tag" --scope "$TF11_SCOPE" -o json | jq -e "$TF11_TAG_ASSIGN_JQ"' \
  "expected policy assignment $PREFIX-require-owner-tag at $TF11_SCOPE pointing at the definition $PREFIX-require-owner-tag"

check "assignment $PREFIX-allowed-locations allows only swedencentral" \
  'az policy assignment show -n "$PREFIX-allowed-locations" --scope "$TF11_SCOPE" -o json | jq -e "$TF11_LOC_ASSIGN_JQ"' \
  "expected policy assignment $PREFIX-allowed-locations of built-in e56962a6-4747-49cd-b67b-bf8b01975c4c with listOfAllowedLocations [\"swedencentral\"]"

check "an untagged $TF11_PROBE is refused (RequestDisallowedByPolicy)" \
  'tf11_probe' \
  "az group create -n $TF11_PROBE without tags must fail with RequestDisallowedByPolicy (new assignments can take minutes to take effect; the grader deletes the group if it was created)"
