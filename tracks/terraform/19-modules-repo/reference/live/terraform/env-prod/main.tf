# One environment's spoke, built by the spoke module, released from the modules repo (tf-19).
# hub.tf finds the hub it peers with; moved.tf records where the resources lived before tf-15.
# The state addresses (module.spoke.*) are the same as with the local module: no moved blocks.

module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v1.0.0"

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
