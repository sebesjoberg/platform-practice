# tf-29 solution

## Approach

1. Create `terraform/observability` (versions, variables, `main.tf`) with the workspace and the
   diagnostic setting copied from landing-zone's `monitoring.tf`; the hub group comes from a data
   source, the tags from a local.
2. **PR 1:** delete `monitoring.tf` from landing-zone and add `removed` blocks there; add
   `import` blocks to observability. Merge: landing-zone forgets, observability imports, in the
   same apply job.
3. **PR 2:** delete the `removed` and `import` blocks. Plan: `No changes.`

## Code (the end state)

`terraform/observability/versions.tf`: as landing-zone's, with `key = "observability.tfstate"`.
`variables.tf`: `prefix` and `owner`, as in landing-zone.

`terraform/observability/main.tf`:

```hcl
locals {
  tags = { owner = var.owner, env = "hub", managed_by = "terraform" }
}

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "hub" {
  name = "rg-${var.prefix}-hub"
}

resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${var.prefix}-platform"
  location            = data.azurerm_resource_group.hub.location
  resource_group_name = data.azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = local.tags
}

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
```

PR 1 only, `terraform/landing-zone/moved-out.tf`:

```hcl
removed {
  from = azurerm_log_analytics_workspace.platform
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_monitor_diagnostic_setting.activity_log
  lifecycle {
    destroy = false
  }
}
```

PR 1 only, `terraform/observability/import.tf`:

```hcl
import {
  to = azurerm_log_analytics_workspace.platform
  id = "/subscriptions/{{SUBSCRIPTION_ID}}/resourceGroups/rg-{{PREFIX}}-hub/providers/Microsoft.OperationalInsights/workspaces/law-{{PREFIX}}-platform"
}

import {
  to = azurerm_monitor_diagnostic_setting.activity_log
  id = "/subscriptions/{{SUBSCRIPTION_ID}}|activity-log-to-law"
}
```

Use the exact casing from `~/.platform-lab/snapshots/tf-29.ids`.

## Commands

```bash
cd "$LIVE_DIR"
git switch -c tf-29-move
# write the files above, git rm terraform/landing-zone/monitoring.tf
git add -A && git commit -m "tf-29: move monitoring into the observability stack"
git push -u origin tf-29-move && gh pr create --fill
# read the plan comment: landing-zone 2 x "no longer be managed", observability 2 to import
gh pr checks --watch && gh pr merge --squash --delete-branch

git switch main && git pull && git switch -c tf-29-cleanup
git rm terraform/landing-zone/moved-out.tf terraform/observability/import.tf
git commit -m "tf-29: drop the removed and import blocks" && git push -u origin tf-29-cleanup
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
```

## Verify

```bash
az monitor log-analytics workspace show -g rg-{{PREFIX}}-hub -n law-{{PREFIX}}-platform --query customerId -o tsv
cat ~/.platform-lab/snapshots/tf-29.guids                     # the same GUID
az monitor diagnostic-settings subscription list --query "[].name" -o tsv   # activity-log-to-law
```

## Cost

Nothing changes: the same workspace with its 0.1 GB daily cap. It now stays up through
`./lab.sh pause` in its own stack, as it did in landing-zone.
