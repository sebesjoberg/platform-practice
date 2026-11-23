# tf-15 solution

## Approach

1. Move the spoke resources of `env-dev` into `terraform/modules/spoke`, and rename them to
   module style (`.this`, the peerings keep their direction names). Everything the module
   needs from outside becomes a variable: the environment values, plus the hub as plain values.
2. In both env stacks, replace those resources with one `module "spoke"` call and keep the hub
   data sources; they feed the module's `hub` and `private_dns_zone_names` inputs.
3. Add one `moved` block per resource. The env stacks have identical code (only the variable
   defaults differ), so the same `moved.tf` goes into both.
4. Harden `stacks.sh` so nothing under `terraform/modules/` is ever a stack.
5. One PR. The plans show only moves; merge, and the pipeline rewrites the addresses in both
   states. Azure doesn't notice.

## Code (the end state)

`terraform/modules/spoke/versions.tf`: the stack's pins, no backend, no provider:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
```

`terraform/modules/spoke/variables.tf`: `env`, `address_space`, `prefix`, `location`, `owner`
(all `string`), plus:

```hcl
variable "hub" {
  type = object({
    resource_group_name = string
    vnet_name           = string
    vnet_id             = string
  })
}

variable "private_dns_zone_names" {
  type = set(string)
}
```

`terraform/modules/spoke/main.tf`: tf-14's `main.tf` (locals, resource group, VNet, subnets,
NSGs, associations) with every `.spoke` renamed to `.this`.

`terraform/modules/spoke/hub.tf`: the spoke side of the hub connection:

```hcl
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.env}"
  resource_group_name       = var.hub.resource_group_name
  virtual_network_name      = var.hub.vnet_name
  remote_virtual_network_id = azurerm_virtual_network.this.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.env}-to-hub"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zone_names # same keys as before: the zone names

  name                  = "link-${azurerm_virtual_network.this.name}"
  resource_group_name   = var.hub.resource_group_name
  private_dns_zone_name = each.key
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.tags
}
```

`terraform/env-dev/main.tf` (identical in env-prod):

```hcl
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
```

`terraform/env-dev/hub.tf` keeps the `locals` and the three data sources; the peerings and
links are gone (they are in the module now).

`terraform/env-dev/moved.tf` (identical in env-prod):

```hcl
moved {
  from = azurerm_resource_group.spoke
  to   = module.spoke.azurerm_resource_group.this
}

moved {
  from = azurerm_virtual_network.spoke
  to   = module.spoke.azurerm_virtual_network.this
}

moved {
  from = azurerm_subnet.spoke
  to   = module.spoke.azurerm_subnet.this
}

moved {
  from = azurerm_network_security_group.spoke
  to   = module.spoke.azurerm_network_security_group.this
}

moved {
  from = azurerm_subnet_network_security_group_association.spoke
  to   = module.spoke.azurerm_subnet_network_security_group_association.this
}

moved {
  from = azurerm_virtual_network_peering.hub_to_spoke
  to   = module.spoke.azurerm_virtual_network_peering.hub_to_spoke
}

moved {
  from = azurerm_virtual_network_peering.spoke_to_hub
  to   = module.spoke.azurerm_virtual_network_peering.spoke_to_hub
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.spoke
  to   = module.spoke.azurerm_private_dns_zone_virtual_network_link.this
}
```

`.github/scripts/stacks.sh`: the discovery line drops `modules/` along with `bootstrap`:

```bash
found=$(grep -rlE --include='*.tf' 'backend[[:space:]]+"azurerm"' terraform |
  xargs -r -n1 dirname | sed 's|^terraform/||' | grep -vxE 'bootstrap|modules(/.*)?' | sort -u || true)
```

## Commands

```bash
git switch -c spoke-module
mkdir -p terraform/modules/spoke
# ...write the module, the module call, moved.tf; copy main.tf/hub.tf/moved.tf to env-prod
terraform fmt -recursive terraform
for s in env-dev env-prod; do terraform -chdir=terraform/$s init -backend=false && terraform -chdir=terraform/$s validate; done
bash .github/scripts/stacks.sh all      # landing-zone env-dev env-prod (no modules/spoke)
git add -A && git commit -m "Extract the spoke module (moved blocks, no destroy)"
git push -u origin spoke-module
gh pr create --fill && gh pr checks --watch
#   env-dev / env-prod: "# azurerm_virtual_network.spoke has moved to module.spoke.azurerm_virtual_network.this"
#   ... and "Plan: 0 to add, 0 to change, 0 to destroy."
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
terraform -chdir=terraform/env-dev init && terraform -chdir=terraform/env-dev state list
#   module.spoke.azurerm_virtual_network.this, module.spoke.azurerm_subnet.this["aca"], ...
cat ~/.platform-lab/snapshots/tf-15.guids
az network vnet show -g rg-{{PREFIX}}-dev -n vnet-{{PREFIX}}-dev --query resourceGuid -o tsv   # unchanged
./lab.sh grade
```

## Cost

Nothing changes in Azure: only the addresses in the state files.
