# tf-04 solution

## Approach

Everything goes into `terraform/bootstrap`, next to the state account. The identity gets
one federated credential per GitHub context it will log in from, and three role assignments:
broad enough for the pipeline to build the platform, but unable to escalate. CI cannot make
itself (or anyone else) Owner, User Access Administrator or even Contributor.

## Code

Add the `http` provider (`hashicorp/http`, `~> 3.6`) to `required_providers` if you look the
repo IDs up like the reference does. Then, in `terraform/bootstrap/identity.tf`:

```hcl
data "azurerm_subscription" "current" {}

# Option A (reference): look the IDs up from GitHub's public API.
data "http" "live_repo" {
  url             = "https://api.github.com/repos/{{GH_OWNER}}/{{LIVE_REPO}}"
  request_headers = { Accept = "application/vnd.github+json" }
}

locals {
  live_repo     = jsondecode(data.http.live_repo.response_body)
  gh_sub_prefix = "repo:${local.live_repo.owner.login}@${local.live_repo.owner.id}/${local.live_repo.name}@${local.live_repo.id}"
  # Option B: paste the output of
  #   gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/oidc/customization/sub --jq .sub_claim_prefix
  # gh_sub_prefix = "repo:{{GH_OWNER}}@1234567/{{LIVE_REPO}}@987654321"

  ci_federated_subjects = {
    gh-main     = "${local.gh_sub_prefix}:ref:refs/heads/main"
    gh-pr       = "${local.gh_sub_prefix}:pull_request"
    gh-env-prod = "${local.gh_sub_prefix}:environment:prod"
  }

  ci_assignable_roles = {
    acr_pull                      = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
    key_vault_secrets_user        = "4633458b-17de-408a-b874-0445c86b69e6"
    reader                        = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    storage_blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  }
  ci_assignable_role_list = join(", ", values(local.ci_assignable_roles))
}

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-{{PREFIX}}-github-ci"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "ci" {
  for_each                  = local.ci_federated_subjects
  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
}

resource "azurerm_role_assignment" "ci_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ci_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
 )
 OR
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.ci_assignable_role_list}}
 )
)
AND
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.ci_assignable_role_list}}
 )
)
EOT
}

resource "azurerm_role_assignment" "ci_state_blob" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}

output "ci_client_id" {
  value = azurerm_user_assigned_identity.ci.client_id
}
```

How to read the condition: an assignment write passes if it *isn't* a role assignment write,
or if the requested role is one of the four. The delete half says the same about the role
of the assignment being deleted.

## Commands

```bash
cd terraform/bootstrap
terraform init -upgrade        # picks up the http provider
terraform plan -out tfplan     # 1 identity, 3 credentials, 3 role assignments
terraform apply tfplan
cd ../..
git add terraform/bootstrap && git commit -m "bootstrap: CI identity with federated credentials" && git push
```

## Verify

```bash
az identity federated-credential list -g rg-{{PREFIX}}-tfstate --identity-name id-{{PREFIX}}-github-ci \
  --query "[].{name:name, subject:subject}" -o table
pid=$(az identity show -g rg-{{PREFIX}}-tfstate -n id-{{PREFIX}}-github-ci --query principalId -o tsv)
az role assignment list --assignee "$pid" --all --query "[].{role:roleDefinitionName, scope:scope}" -o table
./lab.sh grade
```

## Cost

Free. Managed identities, federated credentials and role assignments cost nothing.
