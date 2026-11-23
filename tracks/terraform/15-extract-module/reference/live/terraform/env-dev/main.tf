# One environment's spoke, built by the spoke module (tf-15). hub.tf finds the hub it peers
# with; moved.tf records where the resources lived before the extraction.

module "spoke" {
  source = "../modules/spoke"

  env           = var.env
  address_space = var.address_space
  prefix        = var.prefix
  location      = var.location
  owner         = var.owner

  hub = {
    resource_group_name = data.azurerm_resource_group.hub.name
    vnet_name           = data.azurerm_virtual_network.hub.name
    vnet_id             = data.azurerm_virtual_network.hub.id
  }
  private_dns_zone_names = keys(data.azurerm_private_dns_zone.hub)
}
