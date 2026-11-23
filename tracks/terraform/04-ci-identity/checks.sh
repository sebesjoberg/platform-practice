# tf-04 checks (sourced by the grader; cwd = LIVE_DIR)

export TF04_RG="rg-$PREFIX-tfstate" TF04_ID="id-$PREFIX-github-ci"
export TF04_CONTAINER_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-tfstate/providers/Microsoft.Storage/storageAccounts/st${PREFIX}tfstate$SUFFIX/blobServices/default/containers/tfstate"
# AcrPull, Key Vault Secrets User, Reader, Storage Blob Data Contributor: the condition must name
# these. Later tasks add data-plane roles (tf-21: Key Vault Secrets Officer), so the check wants
# these four and never a privileged role.
export TF04_ROLES="7f951dda-4ed3-4680-a7ca-43fe172d538d 4633458b-17de-408a-b874-0445c86b69e6 acdd72a7-3385-48ef-bd42-f606fba81ae7 ba92f5b4-2d11-453d-a403-e96b0029c9fe"
# Owner, User Access Administrator, Role Based Access Control Administrator, Contributor
export TF04_PRIVILEGED="8e3af657-a8ff-443c-a75c-2fe8c4bcb635 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9 f58310d9-a9f6-439a-9e8d-f62e7b41a168 b24988ac-6180-42a0-ab88-20f7382dd24c"
export TF04_ISSUER_JQ='length >= 3 and all(.[]; .issuer == "https://token.actions.githubusercontent.com" and .audiences == ["api://AzureADTokenExchange"])'
export TF04_CONTRIB_JQ='any(.[]; .roleDefinitionName == "Contributor" and .scope == ("/subscriptions/" + env.SUBSCRIPTION_ID))'
export TF04_RBAC_JQ='[.[] | select(.roleDefinitionName == "Role Based Access Control Administrator" and .scope == ("/subscriptions/" + env.SUBSCRIPTION_ID) and .conditionVersion == "2.0") | (.condition // "") as $c | ($c | test("roleAssignments/write")) and ($c | test("roleAssignments/delete")) and ([$c | scan("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}") | ascii_downcase] | unique) as $g | ($g | contains(env.TF04_ROLES | split(" "))) and ($g - (env.TF04_PRIVILEGED | split(" ")) == $g)] | any'
export TF04_BLOB_JQ='any(.[]; .roleDefinitionName == "Storage Blob Data Contributor" and (.scope | ascii_downcase) == (env.TF04_CONTAINER_SCOPE | ascii_downcase))'

# tf04_sub_prefix: the repo's OIDC subject prefix as GitHub reports it (immutable format as fallback).
tf04_sub_prefix() {
  local p
  p="$(gh api "repos/$GH_OWNER/$LIVE_REPO/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null || true)"
  [[ -n "$p" ]] || p="$(gh api "repos/$GH_OWNER/$LIVE_REPO" --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"')"
  printf '%s\n' "$p"
}
# tf04_pid: principal ID of the CI identity.
tf04_pid() { az identity show -g "$TF04_RG" -n "$TF04_ID" --query principalId -o tsv; }
export -f tf04_sub_prefix tf04_pid

check_code "CI identity is declared in bootstrap" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_user_assigned_identity\"" terraform/bootstrap --include="*.tf"' \
  "no azurerm_user_assigned_identity in terraform/bootstrap"

check_code "federated identity credentials are declared in bootstrap" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_federated_identity_credential\"" terraform/bootstrap --include="*.tf"' \
  "no azurerm_federated_identity_credential in terraform/bootstrap"

check_code "RBAC Administrator assignment with a version 2.0 condition is declared" \
  'grep --exclude-dir=.terraform -rqsE "Role Based Access Control Administrator|f58310d9-a9f6-439a-9e8d-f62e7b41a168" terraform/bootstrap --include="*.tf" && grep --exclude-dir=.terraform -rqsE "condition_version[[:space:]]*=[[:space:]]*\"2\.0\"" terraform/bootstrap --include="*.tf"' \
  "terraform/bootstrap needs a Role Based Access Control Administrator assignment with condition_version = \"2.0\""

check "$TF04_ID exists in $TF04_RG ($LOCATION)" \
  '[[ "$(az identity show -g "$TF04_RG" -n "$TF04_ID" --query location -o tsv)" == "$LOCATION" ]]' \
  "expected managed identity $TF04_ID in $TF04_RG, location $LOCATION"

check "federated credential gh-main trusts pushes to main" \
  '[[ "$(az identity federated-credential show -g "$TF04_RG" --identity-name "$TF04_ID" -n gh-main --query subject -o tsv)" == "$(tf04_sub_prefix):ref:refs/heads/main" ]]' \
  "gh-main subject must be <sub_claim_prefix>:ref:refs/heads/main (see gh api repos/$GH_OWNER/$LIVE_REPO/actions/oidc/customization/sub)"

check "federated credential gh-pr trusts pull requests" \
  '[[ "$(az identity federated-credential show -g "$TF04_RG" --identity-name "$TF04_ID" -n gh-pr --query subject -o tsv)" == "$(tf04_sub_prefix):pull_request" ]]' \
  "gh-pr subject must be <sub_claim_prefix>:pull_request"

check "federated credential gh-env-prod trusts the prod environment" \
  '[[ "$(az identity federated-credential show -g "$TF04_RG" --identity-name "$TF04_ID" -n gh-env-prod --query subject -o tsv)" == "$(tf04_sub_prefix):environment:prod" ]]' \
  "gh-env-prod subject must be <sub_claim_prefix>:environment:prod"

check "federated credentials use GitHub's issuer and audience" \
  'az identity federated-credential list -g "$TF04_RG" --identity-name "$TF04_ID" -o json | jq -e "$TF04_ISSUER_JQ"' \
  "issuer must be https://token.actions.githubusercontent.com and audience api://AzureADTokenExchange"

check "CI identity is Contributor on the subscription" \
  'pid="$(tf04_pid)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --all -o json | jq -e "$TF04_CONTRIB_JQ"' \
  "$TF04_ID needs Contributor at /subscriptions/$SUBSCRIPTION_ID"

check "RBAC Administrator allows AcrPull, Key Vault Secrets User, Reader, Storage Blob Data Contributor, no privileged role" \
  'pid="$(tf04_pid)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --all -o json | jq -e "$TF04_RBAC_JQ"' \
  "need Role Based Access Control Administrator on the subscription with a 2.0 condition on write and delete that names those four role GUIDs and never Owner, User Access Administrator, Role Based Access Control Administrator or Contributor"

check "CI identity has Storage Blob Data Contributor on the tfstate container" \
  'pid="$(tf04_pid)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --all -o json | jq -e "$TF04_BLOB_JQ"' \
  "$TF04_ID needs Storage Blob Data Contributor scoped to the tfstate container"
