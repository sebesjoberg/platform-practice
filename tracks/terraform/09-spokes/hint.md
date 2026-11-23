# tf-09 hints

Docs:
- `for_each`, `each.key`, `each.value`: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- Nested loops with `flatten`/`merge` and `for`: https://developer.hashicorp.com/terraform/language/functions/flatten
- `cidrsubnet`: https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
- `azurerm_virtual_network_peering`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering
- Subnet delegation: https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview

Traps:
- **Environments × subnets is a nested loop**, but `for_each` takes one flat map. Build it in
  `locals` with a `for` inside a `for` and merge the inner maps:
  `merge([for env in var.envs : { for name, s in local.layout : "${env}-${name}" => {...} }]...)`.
  The `...` expands the list into arguments. Keys like `"dev-app"` are stable addresses.
- **Keys, not positions.** Don't use `count` or a list index: removing `dev` would shift
  `prod` and force it to be replaced.
- **`cidrsubnet(prefix, newbits, netnum)`**: from a `/16`, `newbits = 8` gives `/24`s
  (`netnum` 1 → `x.1.0/24`) and `newbits = 7` gives `/23`s (`netnum` 2 → `x.4.0/23`).
  Writing the six prefixes out in a map is fine too.
- **A delegation only on `snet-aca`**: a `dynamic "delegation"` block whose `for_each` is an
  empty list for the other subnets. Set `actions` to
  `["Microsoft.Network/virtualNetworks/subnets/join/action"]`; Azure fills it in anyway,
  and leaving it out shows a change on every plan.
- **Peering is one-way.** Hub → spoke alone shows `Initiated`; both sides make it
  `Connected`. The hub-side peering lives in `rg-{{PREFIX}}-hub` on `vnet-{{PREFIX}}-hub`.
- **No gateway transit** or forwarded traffic options: there's no gateway or firewall in the
  hub, and the spokes don't need to talk to each other.
