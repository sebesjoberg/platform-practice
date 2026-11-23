# tf-13 hints

Docs:
- `azurerm_log_analytics_workspace` (`daily_quota_gb`): https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace
- `azurerm_monitor_diagnostic_setting`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting
- Activity Log categories and export: https://learn.microsoft.com/azure/azure-monitor/platform/activity-log
- Daily cap: https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap

Traps:
- **The subscription is the target.** `target_resource_id = data.azurerm_subscription.current.id`
  (`/subscriptions/<guid>`), the data source from tf-11. There's no separate "activity log"
  resource type in azurerm.
- **Categories, not category groups.** Subscription diagnostic settings take individual
  `enabled_log { category = "Administrative" }` blocks. A `dynamic "enabled_log"` over a set
  keeps it short.
- **`daily_quota_gb` is a number**, `0.1`. `-1` (the default) means no cap.
- **30 days is the minimum and the free retention** for `PerGB2018`. Less is rejected.
- **No metrics block for the subscription**: the Activity Log has logs only.
- **First data takes a while.** Empty queries in the first minutes don't mean it failed;
  any change (e.g. this very apply) produces an `Administrative` event.
