# CI identity for GitHub Actions: a user-assigned managed identity with federated credentials
# (no app registration, no client secret). Applied locally only; CI never manages bootstrap.

data "azurerm_subscription" "current" {}

# GitHub repos created after 2026-07-15 use immutable OIDC subjects:
#   repo:OWNER@OWNER_ID/REPO@REPO_ID:<context>
# The IDs come from GitHub's public API (the repo is public, no token needed).
data "http" "live_repo" {
  url = "https://api.github.com/repos/{{GH_OWNER}}/{{LIVE_REPO}}"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub API did not return {{GH_OWNER}}/{{LIVE_REPO}} (status ${self.status_code})."
    }
  }
}

locals {
  live_repo     = jsondecode(data.http.live_repo.response_body)
  gh_sub_prefix = "repo:${local.live_repo.owner.login}@${local.live_repo.owner.id}/${local.live_repo.name}@${local.live_repo.id}"

  ci_federated_subjects = {
    gh-main     = "${local.gh_sub_prefix}:ref:refs/heads/main"
    gh-pr       = "${local.gh_sub_prefix}:pull_request"
    gh-env-prod = "${local.gh_sub_prefix}:environment:prod"
  }

  # Built-in roles the CI identity may hand out (role definition GUIDs).
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
  for_each = local.ci_federated_subjects

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

# Contributor can't assign roles. RBAC Administrator can, but the condition limits it to
# the four roles above, both for creating and for deleting assignments.
resource "azurerm_role_assignment" "ci_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI may assign only AcrPull, Key Vault Secrets User, Reader and Storage Blob Data Contributor."
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

# State access for the pipeline: data plane on the tfstate container only.
resource "azurerm_role_assignment" "ci_state_blob" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}
