# tf-12 hints

Docs:
- `azurerm_consumption_budget_subscription`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_subscription
- `azurerm_monitor_action_group`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group
- Environment variables as Terraform inputs (`TF_VAR_name`): https://developer.hashicorp.com/terraform/cli/config/environment-variables#tf_var_name
- Budgets and their alerts: https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets

Traps:
- **Where does a personal value go in a public GitOps repo?** Not in a `.tf` file, not in a
  tfvars file (gitignored, so CI never sees it). A GitHub variable, mapped to `TF_VAR_...` in
  the workflow. It's an `env:` entry; at workflow level it reaches both jobs at once.
- **`TF_VAR_` is case-sensitive after the prefix**: `TF_VAR_budget_email` for
  `variable "budget_email"`.
- **A missing GitHub variable doesn't leave the variable unset.** `${{ vars.BUDGET_EMAIL }}`
  of an unknown variable is an empty string, so Terraform gets `TF_VAR_budget_email=""` and
  your validation fails ("budget_email must be an email address ..."). That's why the
  validation matters: without it, the action group would be planned with an empty address.
  (Run locally without the variable at all, `plan -input=false` stops with "No value for
  required variable" instead.)
- **`sensitive = true`** hides the value in plan output. Plans become public PR comments in
  this repo.
- **The start date must be the first of a month** and changing it replaces the budget.
  `formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())` plus
  `lifecycle { ignore_changes = [time_period] }`, or a fixed date in the current month.
- **`subscription_id` takes the resource ID** (`/subscriptions/<guid>`), i.e.
  `data.azurerm_subscription.current.id`, not the bare GUID.
- **Actual vs. forecasted:** `threshold_type = "Actual"` fires on money already spent,
  `"Forecasted"` on the projection for the month. Both alert via `contact_groups`.
- **The action group lives in `global`.** The allowed-locations policy from tf-11 skips
  `global`, so it's not blocked.
