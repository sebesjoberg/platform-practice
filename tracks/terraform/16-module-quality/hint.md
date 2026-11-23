# tf-16 hints

Docs:
- Input variables, `description` and custom `validation`: https://developer.hashicorp.com/terraform/language/values/variables
- Version constraints, with best practices for modules vs. root modules: https://developer.hashicorp.com/terraform/language/expressions/version-constraints
- Standard module structure (README, variables, outputs): https://developer.hashicorp.com/terraform/language/modules/develop/structure
- terraform-docs, inject mode: https://terraform-docs.io/user-guide/configuration/output/

Traps:
- **`>=` in modules, `~>` in stacks.** The root module (stack) decides which provider version
  actually runs: its `~> 4.81` (and from tf-30 its lock file) picks one version for everything
  in that stack, modules included. A module only states the range it works with. The lower
  bound is the oldest version whose features it uses, and it stays there when the stacks move
  on to 4.90. Modules that pin tightly (`~> 4.85.0`, or `= 4.85.0`) leave a stack that uses two
  of them with no version that satisfies both, and every upgrade waits for a module release.
- **Why `< 5.0` all the same.** azurerm 5.x exists and renames arguments this module uses (the
  DNS zone link takes `private_dns_zone_id` there). With only `>= 4.81`, anything that runs the
  module on its own, such as `terraform test` in tf-17 or the modules repo's CI in tf-19, gets
  the newest 5.x and fails. Cap at the next major version you haven't tested; raise the cap in
  a release once you have.
- **Validation runs on the module's inputs, at plan time**, before anything reaches Azure.
  `condition` may only refer to the variable itself (since Terraform 1.9 also to other
  variables). `can(cidrhost(var.address_space, 0))` is the usual way to say "a CIDR block".
- **The module's variables have no defaults.** The stacks hold the lab values. A required input
  without a default is a feature: nobody calls the module without thinking about it.
- **terraform-docs only rewrites between the markers** in inject mode. Write the intro and the
  usage example above them by hand; re-run terraform-docs whenever an input or output changes.
  Optional: `--output-check` makes terraform-docs fail when the README is stale, handy in CI.
- **`No changes.`** Descriptions, validations, outputs, constraints and a README don't touch
  Azure. If an env plan shows a change, something in a resource block changed by accident.
