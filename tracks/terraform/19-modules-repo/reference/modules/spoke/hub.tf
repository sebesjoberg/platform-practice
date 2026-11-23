# The spoke's side of the hub connection: both peering directions and the private DNS zone
# links. The module takes the hub as inputs; it never looks the hub up itself.

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.env}"
  resource_group_name       = var.hub.resource_group_name
  virtual_network_name      = var.hub.vnet_name
  remote_virtual_network_id = azurerm_virtual_network.this.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.env}-to-hub"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zone_names

  name                  = "link-${azurerm_virtual_network.this.name}"
  resource_group_name   = var.hub.resource_group_name
  private_dns_zone_name = each.key
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.tags
}
