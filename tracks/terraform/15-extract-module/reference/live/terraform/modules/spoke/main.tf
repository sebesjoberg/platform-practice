# One environment's spoke: resource group, VNet, subnets and their NSGs. Extracted from the env
# stacks in tf-15; the stacks moved their state here with moved blocks (no destroy).

locals {
  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
  }

  # Same layout in every spoke; cidrsubnet() cuts it out of the /16.
  subnet_layout = {
    app = { newbits = 8, netnum = 1, delegation = null }                         # x.1.0/24
    pe  = { newbits = 8, netnum = 2, delegation = null }                         # x.2.0/24
    aca = { newbits = 7, netnum = 2, delegation = "Microsoft.App/environments" } # x.4.0/23
  }

  subnets = {
    for name, s in local.subnet_layout : name => {
      prefix     = cidrsubnet(var.address_space, s.newbits, s.netnum)
      delegation = s.delegation
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}-${var.env}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.prefix}-${var.env}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = "delegation"

      service_delegation {
        name    = delegation.value
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.subnets

  name                = "nsg-${var.prefix}-${var.env}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}
