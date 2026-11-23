# Private DNS (tf-10): one zone per private-link service. The hub link lives here; each
# environment stack links its own VNet (tf-14).

locals {
  private_dns_zones = toset([
    "privatelink.vaultcore.azure.net",   # Key Vault (tf-21)
    "privatelink.blob.core.windows.net", # Storage blobs
  ])
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.key
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.tags["hub"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = local.private_dns_zones

  name                 = "link-${azurerm_virtual_network.hub.name}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id # 5.0: replaces resource_group_name + private_dns_zone_name
  virtual_network_id   = azurerm_virtual_network.hub.id
  registration_enabled = false
  tags                 = local.tags["hub"]
}
