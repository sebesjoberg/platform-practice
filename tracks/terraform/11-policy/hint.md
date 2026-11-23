# tf-11 hints

Docs:
- Policy definition structure (`mode`, `if`/`then`, `field`, `exists`, `like`): https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-basics
- `azurerm_policy_definition` and `azurerm_subscription_policy_assignment`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment
- Built-in definitions, *General* section (follow *Allowed locations* to its rule): https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies#general
- Resource Policy Contributor: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/management-and-governance#resource-policy-contributor

Traps:
- **Order: bootstrap first.** If the PR merges before the CI identity holds Resource Policy
  Contributor, the apply fails with `AuthorizationFailed` on
  `Microsoft.Authorization/policyDefinitions/write`. The PR's *plan* works either way: reading
  needs no write permission. A fresh role assignment can take a few minutes; re-run the failed
  workflow.
- **`mode = "All"` for resource groups.** `Indexed` only evaluates resource types that support
  tags *and* location, which leaves resource groups out. That's why the built-in Allowed
  locations (Indexed) never blocks a resource group in another region; there's a separate
  built-in for that, not needed here.
- **`global` is exempt in the built-in.** Its rule requires `location notIn the list` *and*
  `location notEquals "global"`. So the private DNS zones and the action group (tf-12) are
  fine with `["swedencentral"]` alone. A custom copy without that clause would block them.
- **Tag test:** `{ "field": "tags['owner']", "exists": "false" }`. Match the type with
  `Microsoft.Resources/subscriptions/resourceGroups` and the name with `like "rg-*"`.
- **`jsonencode()` the rule** instead of a heredoc. Terraform then compares the parsed JSON,
  so whitespace never shows up as a diff.
- **Built-in definitions by name (GUID).** `data "azurerm_policy_definition"` with
  `name = "e56962a6-4747-49cd-b67b-bf8b01975c4c"` is unambiguous; display names are not
  guaranteed unique.
- **Existing resources aren't touched.** Deny applies to creates and updates. Everything the
  lab built is tagged and in Sweden Central already, so nothing breaks.
