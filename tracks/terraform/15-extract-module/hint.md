# tf-15 hints

Docs:
- Refactoring with `moved` blocks, including moving into a module: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring
- Writing a module: https://developer.hashicorp.com/terraform/language/modules/develop
- Providers in modules (why a module has no `provider` block): https://developer.hashicorp.com/terraform/language/modules/develop/providers

Traps:
- **Don't copy `versions.tf` as it is.** A `backend` block in a module is ignored with a warning.
  A `provider` block makes it a "legacy module" that can't be used with `for_each`, `count` or
  `depends_on`. Keep only `required_version` and `required_providers`. The stack's provider
  configuration reaches the module on its own.
- **Why the `stacks.sh` change.** Discovery treats every directory with a `backend "azurerm"`
  block as a stack. A module that got one by mistake would be planned and applied as a stack
  of its own, with its own state. Exclude `modules/` by path; one more `grep` pattern does it.
- **A whole-resource `moved` takes every instance with it:**
  `from = azurerm_subnet.spoke`, `to = module.spoke.azurerm_subnet.this` moves `["app"]`,
  `["pe"]` and `["aca"]` at once. It only works if the `for_each` keys stay the same: the
  subnets keyed by `app`/`pe`/`aca`, the DNS links keyed by zone name. Use
  `for_each = var.private_dns_zone_names` in the module and pass
  `keys(data.azurerm_private_dns_zone.hub)` from the stack.
- **`moved`, not `removed` + `import`.** tf-14 moved resources between two states, which
  `moved` can't do. This refactor stays inside each stack's own state, so `moved` is enough,
  and it needs no resource IDs.
- **Read both env plans.** You want "has moved to" for every resource and
  `Plan: 0 to add, 0 to change, 0 to destroy.` A "change" means the module builds something slightly
  different (often a tag or the delegation). "must be replaced" means don't merge: fix the code.
- **`terraform init` after adding a module.** Locally, `terraform validate` fails with "Module
  not installed" until `init` has run again. CI runs `init` on every run.
- **Keep the `moved` blocks.** Unlike an `import`, a `moved` block whose old address isn't in
  the state does nothing, so pause/resume and rebuilds are fine. It still migrates any state
  that has the old addresses. Delete them only once no such state can exist.
- **Data sources stay in the stack.** The module takes plain values (`hub`,
  `private_dns_zone_names`). That keeps it free of Azure lookups, which tf-17's tests rely on.
