# tf-08 solution

## Approach

One `locals` map holds the address plan. The subnets, NSGs and associations all use
`for_each` over it, so adding a subnet later is a one-line change. The NSGs have no custom
rules: the default rules are exactly "VNet-internal yes, internet inbound no".

## Code

`terraform/landing-zone/network.tf`:

```hcl
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
}

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
```

The addresses in state are `azurerm_subnet.hub["runner"]` and so on. Keys are names, not
list positions, so removing `shared` later never renumbers `runner`.

## Commands

```bash
terraform -chdir=terraform/landing-zone fmt
terraform -chdir=terraform/landing-zone validate
git switch -c hub-network
git add terraform/landing-zone && git commit -m "landing-zone: hub network"
git push -u origin hub-network
gh pr create --fill && gh pr checks --watch     # Plan: 10 to add, 0 to change, 0 to destroy.
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az network vnet show -g rg-{{PREFIX}}-hub -n vnet-{{PREFIX}}-hub --query addressSpace.addressPrefixes
az network vnet subnet list -g rg-{{PREFIX}}-hub --vnet-name vnet-{{PREFIX}}-hub \
  --query "[].{name:name, prefix:addressPrefix, nsg:networkSecurityGroup.id}" -o table
./lab.sh grade
```

## Cost

VNets, subnets and NSGs are free. Traffic across peerings (tf-09) costs a little per GB; the lab
moves almost nothing.
