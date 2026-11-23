# One environment: its spoke and its workload foundation, from the same modules and releases as
# env-dev. tf-24 completes the canary of tf-20: dev ran spoke v2.0.0 first, now prod follows.
# hub.tf finds the hub it peers with; moved.tf records where the resources lived before tf-15.

module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v2.0.0"

  env       = var.env
  vnet_cidr = var.address_space # renamed input in v2.0.0; the stack keeps its own variable
  prefix    = var.prefix
  location  = var.location
  owner     = var.owner

  hub = {
    resource_group_name = data.azurerm_resource_group.hub.name
    vnet_name           = data.azurerm_virtual_network.hub.name
    vnet_id             = data.azurerm_virtual_network.hub.id
  }
  private_dns_zone_names = keys(data.azurerm_private_dns_zone.hub)
}

module "app_env" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//app-env?ref=v2.1.0"

  env                        = var.env
  prefix                     = var.prefix
  suffix                     = var.suffix
  location                   = var.location
  owner                      = var.owner
  resource_group_name        = module.spoke.resource_group_name
  private_endpoint_subnet_id = module.spoke.subnet_ids["pe"]
  key_vault_dns_zone_id      = data.azurerm_private_dns_zone.hub["privatelink.vaultcore.azure.net"].id

  secrets = {
    greeting = "Hello from ${var.prefix} ${var.env}"
  }
}
