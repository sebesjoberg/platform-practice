# The hub belongs to landing-zone. This stack only reads it, by name, through data sources:
# no access to landing-zone's state file, no coupling to how landing-zone is written.

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

# Both directions of the peering belong to the spoke: it's created and destroyed with it.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.env}"
  resource_group_name       = data.azurerm_resource_group.hub.name
  virtual_network_name      = data.azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.env}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = data.azurerm_private_dns_zone.hub

  name                  = "link-${azurerm_virtual_network.spoke.name}"
  resource_group_name   = data.azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags
}
