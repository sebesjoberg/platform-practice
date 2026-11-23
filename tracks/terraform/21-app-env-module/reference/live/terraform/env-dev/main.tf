# One environment: its spoke (tf-19) and its workload foundation (tf-21), both from the modules repo.
# dev runs v2 first (tf-20); env-prod stays on v1 until dev has proven it.
# hub.tf finds the hub it peers with; moved.tf records where the resources lived before tf-15.
# The state addresses (module.spoke.*) are the same as with the local module: no moved blocks.

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

# The workload foundation (tf-21): the app's identity and the environment's Key Vault, in the
# spoke's resource group, with the vault's private endpoint in snet-pe. A release of the whole
# modules repo: v2.1.0 adds app-env and leaves spoke as it was in v2.0.0.
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

  # A demo value, not a secret: real secrets never live in the repo. CI writes it with its
  # Key Vault Secrets Officer role; the app reads it in tf-23.
  secrets = {
    greeting = "Hello from ${var.prefix} ${var.env}"
  }
}
