# The registry belongs to the shared stack (tf-22), which runs before this one. This stack finds
# it by name and lets its own app identity pull from it: whoever consumes a shared service asks
# for access in its own stack, so shared never needs to know the environments.
data "azurerm_container_registry" "shared" {
  name                = "acr${var.prefix}${var.suffix}"
  resource_group_name = "rg-${var.prefix}-shared"
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = module.app_env.identity_principal_id
  principal_type       = "ServicePrincipal"
}
