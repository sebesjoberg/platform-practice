# The registry belongs to the shared stack (tf-22). This stack lets its own app identity pull from
# it: whoever consumes a shared service asks for access in its own stack, so shared never needs
# to know the environments.
#
# No data source: on the pull request that adds the registry, the plan runs before anything is
# applied, and a data source would fail ("not found"). An Azure resource ID is built from names,
# so this stack writes it down. On merge the pipeline applies shared before env-dev, so the
# registry exists when the role assignment is created.

data "azurerm_client_config" "current" {}

locals {
  acr_name = "acr${var.prefix}${var.suffix}"
  acr_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/rg-${var.prefix}-shared/providers/Microsoft.ContainerRegistry/registries/${local.acr_name}"
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = local.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.app_env.identity_principal_id
  principal_type       = "ServicePrincipal"
}
