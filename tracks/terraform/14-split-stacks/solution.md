# tf-14 solution

## Approach

1. Write `terraform/env-dev` as a single-environment copy of the spoke code: no `for_each`
   over environments any more, `var.env` and `var.address_space` instead. The hub comes from
   data sources. `env-prod` is the same code with other defaults (`prod`, `10.2.0.0/16`).
   The duplication is deliberate for now; tf-15 turns it into a module.
2. **PR 1 (the move):** landing-zone loses the spoke code and gains `removed` blocks with
   `destroy = false`; the env stacks get `import` blocks. One merge, one apply run: landing-zone
   forgets (it's first in `STACK_ORDER`), then env-dev and env-prod import. Nothing is created
   or destroyed.
3. **PR 2 (the cleanup):** delete the `import` and `removed` blocks. They've done their job, and
   an `import` of an object that doesn't exist fails, which would break `./lab.sh resume` after
   a pause and any rebuild from scratch.

## Code (the end state)

`terraform/env-dev/versions.tf`: as landing-zone's, with `key = "env-dev.tfstate"`.

`terraform/env-dev/variables.tf`: `prefix`, `location`, `owner` as in landing-zone, plus:

```hcl
variable "env" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "address_space" {
  type    = string
  default = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a /16 CIDR block."
  }
}
```

`terraform/env-dev/main.tf`:

```hcl
locals {
  tags = { owner = var.owner, env = var.env, managed_by = "terraform" }

  subnet_layout = {
    app = { newbits = 8, netnum = 1, delegation = null }
    pe  = { newbits = 8, netnum = 2, delegation = null }
    aca = { newbits = 7, netnum = 2, delegation = "Microsoft.App/environments" }
  }
  subnets = {
    for name, s in local.subnet_layout : name => {
      prefix     = cidrsubnet(var.address_space, s.newbits, s.netnum)
      delegation = s.delegation
    }
  }
}

resource "azurerm_resource_group" "spoke" {
  name     = "rg-${var.prefix}-${var.env}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${var.prefix}-${var.env}"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  address_space       = [var.address_space]
  tags                = local.tags
}

# azurerm_subnet.spoke, azurerm_network_security_group.spoke and
# azurerm_subnet_network_security_group_association.spoke: as in tf-09, but
# for_each = local.subnets, names "snet-${each.key}" / "nsg-${var.prefix}-${var.env}-${each.key}".
```

`terraform/env-dev/hub.tf`:

```hcl
locals {
  private_dns_zones = toset(["privatelink.vaultcore.azure.net", "privatelink.blob.core.windows.net"])
}

data "azurerm_resource_group" "hub" {
  name = "rg-${var.prefix}-hub"
}

data "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub"
  resource_group_name = data.azurerm_resource_group.hub.name
}

data "azurerm_private_dns_zone" "hub" {
  for_each            = local.private_dns_zones
  name                = each.key
  resource_group_name = data.azurerm_resource_group.hub.name
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.env}"
  resource_group_name       = data.azurerm_resource_group.hub.name
  virtual_network_name      = data.azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.env}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each              = data.azurerm_private_dns_zone.hub
  name                  = "link-${azurerm_virtual_network.spoke.name}"
  resource_group_name   = data.azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags
}
```

landing-zone: delete `spokes.tf` and the spoke links in `dns.tf`, drop `var.envs`, and keep
only `local.tags["hub"]` (`tags = { hub = merge(local.base_tags, { env = "hub" }) }`).

### PR 1 only: the migration blocks

`terraform/landing-zone/moved-out.tf`:

```hcl
removed {
  from = azurerm_resource_group.spoke
  lifecycle { destroy = false }
}
# ...one block each for azurerm_virtual_network.spoke, azurerm_subnet.spoke,
# azurerm_network_security_group.spoke, azurerm_subnet_network_security_group_association.spoke,
# azurerm_virtual_network_peering.hub_to_spoke, azurerm_virtual_network_peering.spoke_to_hub,
# azurerm_private_dns_zone_virtual_network_link.spoke
```

`terraform/env-dev/imports.tf` (identical in env-prod, thanks to `var.env`):

```hcl
locals {
  sub     = "/subscriptions/{{SUBSCRIPTION_ID}}"
  hub_rg  = "${local.sub}/resourceGroups/rg-${var.prefix}-hub"
  rg_id   = "${local.sub}/resourceGroups/rg-${var.prefix}-${var.env}"
  vnet_id = "${local.rg_id}/providers/Microsoft.Network/virtualNetworks/vnet-${var.prefix}-${var.env}"
}

import {
  to = azurerm_resource_group.spoke
  id = local.rg_id
}

import {
  to = azurerm_virtual_network.spoke
  id = local.vnet_id
}

import {
  for_each = local.subnets
  to       = azurerm_subnet.spoke[each.key]
  id       = "${local.vnet_id}/subnets/snet-${each.key}"
}

import {
  for_each = local.subnets
  to       = azurerm_network_security_group.spoke[each.key]
  id       = "${local.rg_id}/providers/Microsoft.Network/networkSecurityGroups/nsg-${var.prefix}-${var.env}-${each.key}"
}

import {
  for_each = local.subnets
  to       = azurerm_subnet_network_security_group_association.spoke[each.key]
  id       = "${local.vnet_id}/subnets/snet-${each.key}" # the association's ID is the subnet's
}

import {
  to = azurerm_virtual_network_peering.spoke_to_hub
  id = "${local.vnet_id}/virtualNetworkPeerings/peer-${var.env}-to-hub"
}

import {
  to = azurerm_virtual_network_peering.hub_to_spoke
  id = "${local.hub_rg}/providers/Microsoft.Network/virtualNetworks/vnet-${var.prefix}-hub/virtualNetworkPeerings/peer-hub-to-${var.env}"
}

import {
  for_each = local.private_dns_zones
  to       = azurerm_private_dns_zone_virtual_network_link.spoke[each.key]
  id       = "${local.hub_rg}/providers/Microsoft.Network/privateDnsZones/${each.key}/virtualNetworkLinks/link-vnet-${var.prefix}-${var.env}"
}
```

## Commands

```bash
cat ~/.platform-lab/snapshots/tf-14.ids        # what moves, by ID

# PR 1: the move
git switch -c split-stacks
git add terraform && git commit -m "Split spokes into env-dev and env-prod (removed + import)"
git push -u origin split-stacks
gh pr create --fill && gh pr checks --watch
#   landing-zone: no destroy; the spokes "will no longer be managed by Terraform"
#   env-dev / env-prod: Plan: 15 to import, 0 to add, 0 to change, 0 to destroy.
gh pr merge --squash --delete-branch && gh run watch

# PR 2: the cleanup
git switch main && git pull
git switch -c split-stacks-cleanup
git rm terraform/landing-zone/moved-out.tf terraform/env-dev/imports.tf terraform/env-prod/imports.tf
git commit -m "Drop the one-shot removed and import blocks"
git push -u origin split-stacks-cleanup
gh pr create --fill && gh pr checks --watch     # No changes. in every stack
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az storage blob list --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} -c tfstate --query "[].name" -o tsv
terraform -chdir=terraform/env-dev init && terraform -chdir=terraform/env-dev state list
cat ~/.platform-lab/snapshots/tf-14.guids     # same as:
az network vnet show -g rg-{{PREFIX}}-dev -n vnet-{{PREFIX}}-dev --query resourceGuid -o tsv
./lab.sh grade
```

## Cost

Nothing changes in Azure. From now on `./lab.sh pause` destroys the spoke stacks too (free
resources anyway), and `resume` rebuilds them.
