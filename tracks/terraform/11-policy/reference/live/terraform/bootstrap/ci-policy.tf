# CI manages Azure Policy from tf-11 on. Contributor excludes Microsoft.Authorization/*, so it
# can't write policy definitions or assignments. Resource Policy Contributor adds exactly that
# (policy definitions, set definitions, assignments, exemptions) and no role assignments.
resource "azurerm_role_assignment" "ci_policy" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Resource Policy Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}
