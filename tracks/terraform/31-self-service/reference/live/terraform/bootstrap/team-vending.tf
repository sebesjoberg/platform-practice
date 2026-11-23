# Team vending (tf-31): the platform owner hands each product team a landing spot, a resource
# group, and lets the pipeline operate inside it, nowhere else. Applied locally by you, the
# subscription Owner, like the rest of bootstrap: CI never widens its own reach.
#
# For each team: rg-<prefix>-<team> (tags), and a Role Based Access Control Administrator
# assignment for the CI identity *on that group only*, with a condition that allows exactly one
# thing: assigning (and removing) Contributor to service principals (managed identities). The
# pipeline then creates the team's identity, federated credential and budget (the team-env
# module) and gives that identity Contributor on its own group. It can't grant Contributor
# anywhere else, nor to a user or a group, nor any other role there.
#
# A new team is one more entry in local.teams, applied here before the team's stack is merged.

locals {
  teams = {
    payments = { env = "dev" }
  }

  contributor_role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c"
}

resource "azurerm_resource_group" "team" {
  for_each = local.teams

  name     = "rg-{{PREFIX}}-${each.key}"
  location = "{{LOCATION}}"
  tags = {
    owner      = "{{OWNER_TAG}}"
    env        = each.value.env
    managed_by = "terraform"
    team       = each.key
  }
}

resource "azurerm_role_assignment" "ci_team_rbac" {
  for_each = local.teams

  scope                = azurerm_resource_group.team[each.key].id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI may assign Contributor to managed identities in the ${each.key} team's group only (tf-31)."
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
