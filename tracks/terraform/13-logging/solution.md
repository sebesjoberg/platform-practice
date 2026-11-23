# tf-13 solution

## Approach

One workspace for the platform in the hub group, capped at 0.1 GB of billable data per day.
The subscription gets a diagnostic setting that streams every Activity Log category into it.
Later tasks (VMs, Container Apps) send their logs to the same workspace.

## Code

`terraform/landing-zone/monitoring.tf`:

```hcl
resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${var.prefix}-platform"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = local.tags["hub"]
}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "activity-log-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  dynamic "enabled_log" {
    for_each = toset(["Administrative", "Security", "ServiceHealth", "Alert",
    "Recommendation", "Policy", "Autoscale", "ResourceHealth"])
    content {
      category = enabled_log.value
    }
  }
}
```

## Commands

```bash
git switch -c logging
git add terraform/landing-zone && git commit -m "landing-zone: Log Analytics and Activity Log export"
git push -u origin logging
gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az monitor log-analytics workspace show -g rg-{{PREFIX}}-hub -n law-{{PREFIX}}-platform \
  --query "{sku:sku.name, retention:retentionInDays, cap:workspaceCapping.dailyQuotaGb}"
az monitor diagnostic-settings subscription list -o table
# after ~15 minutes:
az monitor log-analytics query -w "$(az monitor log-analytics workspace show -g rg-{{PREFIX}}-hub \
  -n law-{{PREFIX}}-platform --query customerId -o tsv)" \
  --analytics-query "AzureActivity | summarize count() by OperationNameValue | top 5 by count_"
./lab.sh grade
```

## Cost

The workspace itself is free; you pay per GB ingested (Activity Log ingestion is free). The
daily cap stops billable ingestion at 0.1 GB per day. That's a few kronor per month at most,
and it survives `./lab.sh pause`.
