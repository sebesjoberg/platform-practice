# Team onboarding (tf-31): the pipeline creates each team's identity and gives it Contributor on
# the team's own resource group. CI's first RBAC Administrator assignment (identity.tf) may only
# hand out data-plane and read roles. This second one allows exactly one more thing: assigning or
# removing Contributor, and only for service principals (managed identities), never users or
# groups. Azure grants an action when any assignment allows it, so the first condition stays as
# strict as it was.
#
# What this trusts: CI is Contributor on the subscription already, so it gains no access itself.
# It could give Contributor to another managed identity at any scope, so code review of every
# role assignment in a pull request is what keeps team grants on the team's own group. RBAC
# conditions can't restrict the scope of an assignment.

locals {
  contributor_role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c"
}

resource "azurerm_role_assignment" "ci_team_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI may assign Contributor to managed identities only: team onboarding (tf-31)."
  condition_version    = "2.0"
  condition            = <<-EOT
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
 )
 OR
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.contributor_role_id}}
  AND
  @Request[Microsoft.Authorization/roleAssignments:PrincipalType] StringEqualsIgnoreCase 'ServicePrincipal'
 )
)
AND
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.contributor_role_id}}
  AND
  @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] StringEqualsIgnoreCase 'ServicePrincipal'
 )
)
EOT
}
