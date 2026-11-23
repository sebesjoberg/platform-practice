# tf-29 hints

Docs:
- `removed` blocks: https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources
- `import` blocks: https://developer.hashicorp.com/terraform/language/import
- Import ID of a diagnostic setting: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting#import
- Workspace ID vs resource ID: https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview

Traps:
- **Same pattern as tf-14.** One PR forgets in one stack and imports in the other. `STACK_ORDER`
  runs landing-zone first and observability later in the same apply job, so nothing is ever
  managed twice or not at all for long.
- **The diagnostic setting has an odd import ID:** the target's resource ID, a pipe, and the
  setting's name: `/subscriptions/{{SUBSCRIPTION_ID}}|activity-log-to-law`. The workspace's is an
  ordinary resource ID (in the snapshot file).
- **Two IDs.** The *resource ID* is built from names: delete the workspace and create one with the
  same name, and it comes back. The *workspace ID* (`customerId`) is a GUID Azure assigns at
  creation; agents, data collection rules and saved queries use it. Only the second proves
  nothing was recreated.
- **Tags must match**, or the import plan shows a change: the workspace carried landing-zone's
  hub tags (`owner`, `env = "hub"`, `managed_by`). Changes are fine to apply, destroys are not.
- **Read the plan of every stack.** landing-zone: `will no longer be managed by Terraform`, twice,
  no destroy. observability: `2 to import, 0 to add, 0 to change, 0 to destroy`.
- **Does anything else use the workspace?** Search all stacks for `azurerm_log_analytics_workspace`
  and `law-`. Nothing references it by address today; a stack that needs it later finds it by
  name with a data source, or reads observability's output.
- **The hub resource group stays where it is.** It belongs to landing-zone; observability reads
  it with `data "azurerm_resource_group"`.
- **Why PR 2.** An `import` block fails when its object doesn't exist, and every rebuild from
  scratch (nuke, the capstone) would fail on it.
