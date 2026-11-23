# tf-10 solution

## Approach

The zone names go into a set. Zones and hub links loop over that set; spoke links loop over
`setproduct(zones, var.envs)`. Hub and spoke links are separate resources so each one is
about one network: in tf-14 the spoke links move to the environment stacks as a whole.

## Code

`terraform/landing-zone/dns.tf`:

```hcl
locals {
  private_dns_zones = toset([
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
  ])

  spoke_dns_links = {
    for pair in setproduct(local.private_dns_zones, var.envs) : "${pair[0]}/${pair[1]}" => {
      zone = pair[0]
      env  = pair[1]
    }
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.key
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.tags["hub"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = local.private_dns_zones
  name                  = "link-${azurerm_virtual_network.hub.name}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags["hub"]
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each              = local.spoke_dns_links
  name                  = "link-${azurerm_virtual_network.spoke[each.value.env].name}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = azurerm_virtual_network.spoke[each.value.env].id
  registration_enabled  = false
  tags                  = local.tags[each.value.env]
}
```

## Commands

```bash
git switch -c private-dns
git add terraform/landing-zone && git commit -m "landing-zone: private DNS zones and links"
git push -u origin private-dns
gh pr create --fill && gh pr checks --watch     # Plan: 8 to add, 0 to change, 0 to destroy.
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
for z in privatelink.vaultcore.azure.net privatelink.blob.core.windows.net; do
  az network private-dns link vnet list -g rg-{{PREFIX}}-hub -z "$z" \
    --query "[].{name:name, registration:registrationEnabled, state:virtualNetworkLinkState}" -o table
done
./lab.sh grade
```

## Cost

About 0.50 USD per zone per month. Links and queries at lab volume are practically free.
