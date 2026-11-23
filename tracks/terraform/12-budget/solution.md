# tf-12 solution

## Approach

The address is the only personal value so far. It lives in a GitHub repo secret (masked in the public run logs, unlike a variable) and reaches
Terraform through `TF_VAR_budget_email`, set once at workflow level so both jobs see it. In
Terraform it's a required, sensitive, validated variable. The action group carries the
receiver; the budget points both alerts at the action group.

## Code

`.github/workflows/terraform.yml`, in the workflow-level `env:` next to the `ARM_*` entries:

```yaml
  # Budget alert address (tf-12) for both jobs: plan needs every variable as much as apply.
  TF_VAR_budget_email: ${{ secrets.BUDGET_EMAIL }}
```

`terraform/landing-zone/variables.tf`:

```hcl
variable "budget_email" {
  description = "Recipient of the budget alerts. CI sets it from the GitHub secret BUDGET_EMAIL."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.budget_email))
    error_message = "budget_email must be an email address (set the GitHub secret BUDGET_EMAIL)."
  }
}
```

`terraform/landing-zone/budget.tf` (`data.azurerm_subscription.current` is in `policy.tf` from tf-11):

```hcl
resource "azurerm_monitor_action_group" "budget" {
  name                = "ag-${var.prefix}-budget"
  resource_group_name = azurerm_resource_group.hub.name
  short_name          = "budget"
  tags                = local.tags["hub"]

  email_receiver {
    name                    = "platform-owner"
    email_address           = var.budget_email
    use_common_alert_schema = true
  }
}

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "budget-${var.prefix}-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = 300
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
```

Running Terraform locally now needs the variable too: `export TF_VAR_budget_email=you@example.com`
before `terraform plan` in `landing-zone`. (`./lab.sh nuke` sets a placeholder for its destroy.)

## Commands

```bash
gh secret set BUDGET_EMAIL --body "you@example.com"
git switch -c budget
git add .github/workflows/terraform.yml terraform/landing-zone
git commit -m "landing-zone: monthly budget with alerts"
git push -u origin budget
gh pr create --fill && gh pr checks --watch      # email_address = (sensitive value)
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az consumption budget show --budget-name budget-{{PREFIX}}-monthly \
  --query "{amount:amount, grain:timeGrain, alerts:notifications}"
az monitor action-group show -g rg-{{PREFIX}}-hub -n ag-{{PREFIX}}-budget --query emailReceivers
./lab.sh grade
```

## If the subscription doesn't support budgets

Budgets depend on the subscription's offer type. If the apply fails on the budget with an error
that the offer or subscription type isn't supported (for example `Budget is not supported`
or `SubscriptionTypeNotSupported`):

1. Keep the action group and the variable; remove only the budget resource and merge that.
2. The Visual Studio subscription still has its own safety net: the spending limit disables the
   subscription when the monthly credit is used up, so you can't be billed beyond it.
3. Watch spend with `./lab.sh cost` (and pause at the end of each day once VMs exist).
4. Tell the lab maintainers: the budget check of this task can't pass on that offer type.

## Cost

Budgets and action-group emails are free.
