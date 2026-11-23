# tf-14 hints

Docs:
- `removed` blocks (forget without destroying): https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources
- `import` blocks, including `for_each`: https://developer.hashicorp.com/terraform/language/import
- Data sources: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network
- `moved` blocks (renaming inside one state): https://developer.hashicorp.com/terraform/language/modules/develop/refactoring

Traps:
- **Why one PR for the move.** Merging runs one `apply` job that applies the stacks in
  `STACK_ORDER`: landing-zone first, then env-dev, then env-prod. In the same run,
  landing-zone *forgets* the spokes and the env stacks *import* them. Split it up and it breaks:
  - only delete the code from landing-zone → its plan **destroys** the spokes;
  - only the `removed` blocks → nothing manages the spokes until a later PR;
  - only the env stacks with imports → two states manage the same resources, and the next
    landing-zone change fights the env stacks.
- **`removed` addresses a whole resource**, all its instances:
  `from = azurerm_subnet.spoke` (no `["dev-app"]`). That's why tf-09/tf-10 kept the spoke
  resources separate from the hub ones. If you have one resource for hub *and* spoke DNS links,
  first `moved` the hub instances to a new resource (instance keys are allowed in `moved`),
  then `removed` the old one; both can be in the same PR.
- **Import IDs are Azure resource IDs.** The snapshot file lists them. The NSG association's
  ID is the subnet's ID. `import` takes `for_each` too, so one block with
  `to = azurerm_subnet.spoke[each.key]` and `id = "${local.vnet_id}/subnets/snet-${each.key}"`
  covers all three subnets of a stack.
- **Read the env stack plans:** `N to import, 0 to add, 0 to change, 0 to destroy`. A
  "change" means your new code differs from what exists (often a tag or the delegation
  `actions`). Fix the code, not Azure.
- **Order of operations in a failed run:** if landing-zone applied but an env stack failed
  (e.g. a typo in an import ID), the resources are simply unmanaged for a moment. Nothing is
  deleted. Fix the ID in a new PR; the import blocks still work.
- **Why PR 2.** An `import` block fails when its object doesn't exist. `./lab.sh pause`
  destroys the env stacks and `resume` recreates them: with import blocks left in, resume
  breaks. Import and removed blocks are one-shot tools; delete them once applied.
- **Data sources read by name**, at plan time. The hub must exist before an env stack can
  plan; that's true from here on (landing-zone is never paused).
- **New stacks need no workflow change**: `.github/scripts/stacks.sh` finds them, and
  `STACK_ORDER` already lists `env-dev env-prod` after `landing-zone`.
