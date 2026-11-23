# Shared services (tf-22): things every environment uses, but no single environment owns.
# The stack runs after landing-zone and before the env stacks (STACK_ORDER), and `./lab.sh
# pause` destroys it. The env stacks find what's here by name, through data sources.

locals {
  tags = {
    owner      = var.owner
    env        = "hub" # shared platform services carry the hub's env tag
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.prefix}-shared"
  location = var.location
  tags     = local.tags
}

# One registry for every environment: an image is built (here: imported) once and promoted by
# tag. Basic is the cheapest SKU. No admin user: pulls authenticate with Entra ID (AcrPull).
resource "azurerm_container_registry" "this" {
  name                = "acr${var.prefix}${var.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}
