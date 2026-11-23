# Cost guardrail (tf-12): a monthly subscription budget that mails the platform owner.

resource "azurerm_monitor_action_group" "budget" {
  name                = "ag-${var.prefix}-budget"
  resource_group_name = azurerm_resource_group.hub.name
  short_name          = "budget" # max 12 characters, shown in SMS/email subjects
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
    # Must be the first of a month. Fixed at creation, see ignore_changes below.
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
    # plantimestamp() moves every month; changing start_date would replace the budget.
    ignore_changes = [time_period]
  }
}
