# tf-10 hints

Docs:
- Private endpoint DNS zone names per service: https://learn.microsoft.com/azure/private-link/private-endpoint-dns
- `azurerm_private_dns_zone_virtual_network_link`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link
- `setproduct`: https://developer.hashicorp.com/terraform/language/functions/setproduct

Traps:
- **Zone names are fixed by Azure.** `privatelink.vaultcore.azure.net` is what Key Vault's
  private endpoint registers into. A typo or your own prefix in the zone name means the
  endpoint resolves to the public IP, and nothing tells you.
- **Zones and links are `global`.** They have no region argument; don't try to set
  `location`. (tf-11's allowed-locations policy ignores `global` for this reason.)
- **Zones × spokes is a product.** `setproduct(local.zones, var.envs)` gives every pair;
  turn it into a map with a `for` expression and a readable key such as
  `"privatelink.vaultcore.azure.net/dev"`.
- **Auto-registration is for VM DNS records**, not for private-link zones. Leave
  `registration_enabled = false`; a VNet can only have one registration-enabled zone link
  anyway.
- **The link name must be unique per zone**, not globally. `link-vnet-{{PREFIX}}-hub` exists
  once in each zone.
