# Hub network (tf-08): shared services, the runner/jump host and private endpoints live here.

locals {
  hub_subnets = {
    shared = "10.0.1.0/24"
    runner = "10.0.2.0/24"
    pe     = "10.0.3.0/24"
  }
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags["hub"]
}

resource "azurerm_subnet" "hub" {
  for_each = local.hub_subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value]

  # Explicit since tf-30, as in the spoke module v3.0.0: default outbound access stays on even if
  # a provider or API default changes.
  default_outbound_access_enabled = true
}

# One NSG per subnet, no custom rules yet: the default rules allow traffic inside the VNet
# (and peered VNets) and deny everything inbound from the internet. Later tasks add only
# the rules they need.
resource "azurerm_network_security_group" "hub" {
  for_each = local.hub_subnets

  name                = "nsg-${var.prefix}-hub-${each.key}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.tags["hub"]
}

resource "azurerm_subnet_network_security_group_association" "hub" {
  for_each = local.hub_subnets

  subnet_id                 = azurerm_subnet.hub[each.key].id
  network_security_group_id = azurerm_network_security_group.hub[each.key].id
}
