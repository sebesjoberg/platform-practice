# Central logging (tf-13): one Log Analytics workspace for the platform, capped at 0.1 GB of
# billable data per day, and the subscription's Activity Log streamed into it.

resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${var.prefix}-platform"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 30  # the free retention period
  daily_quota_gb      = 0.1 # stops billable ingestion for the day once reached
  tags                = local.tags["hub"]
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
