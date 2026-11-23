# Private DNS (tf-10): one zone per private-link service, linked to every VNet so private
# endpoints resolve to private IPs everywhere.

locals {
  private_dns_zones = toset([
    "privatelink.vaultcore.azure.net",   # Key Vault (tf-21)
    "privatelink.blob.core.windows.net", # Storage blobs
  ])

  # One entry per zone and spoke: "privatelink.vaultcore.azure.net/dev", ...
  spoke_dns_links = {
    for pair in setproduct(local.private_dns_zones, var.envs) : "${pair[0]}/${pair[1]}" => {
      zone = pair[0]
      env  = pair[1]
    }
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.key
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.tags["hub"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = local.private_dns_zones

  name                  = "link-${azurerm_virtual_network.hub.name}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags["hub"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = local.spoke_dns_links

  name                  = "link-${azurerm_virtual_network.spoke[each.value.env].name}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = azurerm_virtual_network.spoke[each.value.env].id
  registration_enabled  = false
  tags                  = local.tags[each.value.env]
}
