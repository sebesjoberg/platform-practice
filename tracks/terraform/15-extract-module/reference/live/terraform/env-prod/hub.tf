# The hub belongs to landing-zone. This stack only reads it, by name, through data sources,
# and hands it to the spoke module: no access to landing-zone's state file.

locals {
  private_dns_zones = toset([
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
  ])
}

data "azurerm_resource_group" "hub" {
  name = "rg-${var.prefix}-hub"
}

data "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub"
  resource_group_name = data.azurerm_resource_group.hub.name
}

data "azurerm_private_dns_zone" "hub" {
  for_each = local.private_dns_zones

  name                = each.key
  resource_group_name = data.azurerm_resource_group.hub.name
}
