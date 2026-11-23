# tf-09 solution

## Approach

Two lookups in `locals`: the address space per environment and one subnet layout shared by
all spokes. A flattened map (`"dev-app"`, `"dev-pe"`, …) drives subnets, NSGs and
associations. Resource groups, VNets and peerings loop over `var.envs` directly. Adding
`test` later means one entry in `var.envs`' validation and one address space.

## Code

`terraform/landing-zone/spokes.tf`:

```hcl
locals {
  spoke_address_space = {
    dev  = "10.1.0.0/16"
    prod = "10.2.0.0/16"
  }

  spoke_subnet_layout = {
    app = { newbits = 8, netnum = 1, delegation = null }                         # x.1.0/24
    pe  = { newbits = 8, netnum = 2, delegation = null }                         # x.2.0/24
    aca = { newbits = 7, netnum = 2, delegation = "Microsoft.App/environments" } # x.4.0/23
  }

  spoke_subnets = merge([
    for env in var.envs : {
      for name, s in local.spoke_subnet_layout : "${env}-${name}" => {
        env        = env
        name       = name
        prefix     = cidrsubnet(local.spoke_address_space[env], s.newbits, s.netnum)
        delegation = s.delegation
      }
    }
  ]...)
}

resource "azurerm_resource_group" "spoke" {
  for_each = var.envs
  name     = "rg-${var.prefix}-${each.key}"
  location = var.location
  tags     = local.tags[each.key]
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = var.envs
  name                = "vnet-${var.prefix}-${each.key}"
  location            = azurerm_resource_group.spoke[each.key].location
  resource_group_name = azurerm_resource_group.spoke[each.key].name
  address_space       = [local.spoke_address_space[each.key]]
  tags                = local.tags[each.key]
}

resource "azurerm_subnet" "spoke" {
  for_each             = local.spoke_subnets
  name                 = "snet-${each.value.name}"
  resource_group_name  = azurerm_resource_group.spoke[each.value.env].name
  virtual_network_name = azurerm_virtual_network.spoke[each.value.env].name
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

resource "azurerm_network_security_group" "spoke" {
  for_each            = local.spoke_subnets
  name                = "nsg-${var.prefix}-${each.value.env}-${each.value.name}"
  location            = azurerm_resource_group.spoke[each.value.env].location
  resource_group_name = azurerm_resource_group.spoke[each.value.env].name
  tags                = local.tags[each.value.env]
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each                  = local.spoke_subnets
  subnet_id                 = azurerm_subnet.spoke[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                  = var.envs
  name                      = "peer-hub-to-${each.key}"
  resource_group_name       = azurerm_resource_group.hub.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke[each.key].id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                  = var.envs
  name                      = "peer-${each.key}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke[each.key].name
  virtual_network_name      = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
}
```

Check the map before you plan: `terraform console` → `local.spoke_subnets` prints all six
entries with their prefixes.

Keep the hub→spoke and spoke→hub peerings as two resources (not one map of four). tf-14 moves
whole resources into per-environment stacks, and that is much easier when each resource is
cleanly "about one spoke".

## Commands

```bash
git switch -c spokes
git add terraform/landing-zone && git commit -m "landing-zone: dev and prod spokes"
git push -u origin spokes
gh pr create --fill && gh pr checks --watch     # Plan: 26 to add, 0 to change, 0 to destroy.
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az network vnet peering list -g rg-{{PREFIX}}-hub --vnet-name vnet-{{PREFIX}}-hub \
  --query "[].{name:name, state:peeringState}" -o table
az network vnet subnet list -g rg-{{PREFIX}}-dev --vnet-name vnet-{{PREFIX}}-dev \
  --query "[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName}" -o table
./lab.sh grade
```

## Cost

Still free while idle. VNet peering is billed per GB that crosses it.
