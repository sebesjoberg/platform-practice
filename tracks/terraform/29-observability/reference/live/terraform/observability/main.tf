# Observability (tf-29): the platform's Log Analytics workspace and the subscription's Activity
# Log export, moved here from landing-zone with removed + import blocks, without destroying
# anything (the workspace keeps its ID, its customerId and its data). Monitoring changes now get
# their own plan, state and reviewers, and a landing-zone change can't touch them.
#
# The workspace stays in the hub's resource group, which landing-zone owns: this stack finds it
# by name. Like landing-zone, this stack survives ./lab.sh pause; ./lab.sh nuke destroys it.

locals {
  tags = {
    owner      = var.owner
    env        = "hub"
    managed_by = "terraform"
  }
}

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "hub" {
  name = "rg-${var.prefix}-hub"
}

# One workspace for the platform, capped at 0.1 GB of billable data per day (tf-13).
resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${var.prefix}-platform"
  location            = data.azurerm_resource_group.hub.location
  resource_group_name = data.azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 30  # the free retention period
  daily_quota_gb      = 0.1 # stops billable ingestion for the day once reached
  tags                = local.tags
}

# Who changed what, which policy denied what: the Activity Log of the whole subscription.
# Its ingestion into Log Analytics is free.
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "activity-log-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  dynamic "enabled_log" {
    for_each = toset(["Administrative", "Security", "ServiceHealth", "Alert", "Recommendation", "Policy", "Autoscale", "ResourceHealth"])

    content {
      category = enabled_log.value
    }
  }
}

output "log_analytics_workspace_id" {
  description = "Resource ID of law-<prefix>-platform, for diagnostic settings in other stacks."
  value       = azurerm_log_analytics_workspace.platform.id
}
