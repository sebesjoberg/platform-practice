---
id: tf-13
title: Central logging
target_minutes: 15
requires: [tf-12]
---
# tf-13 Central logging

Last week someone asked "who deleted that resource group?" and nobody could answer. The CTO
wants one place for platform logs, starting with the subscription's Activity Log, and a hard
cap so logging can never eat the budget.

## Deliverables

In `terraform/landing-zone`:

- [ ] Log Analytics workspace `law-{{PREFIX}}-platform` in `rg-{{PREFIX}}-hub` (hub tags):
  - SKU `PerGB2018`
  - retention `30` days
  - daily cap `0.1` GB
- [ ] A diagnostic setting on the **subscription** that sends the Activity Log to that
      workspace, with at least the categories `Administrative`, `Security` and `Policy`
      (all categories is fine: Activity Log ingestion is free).
- [ ] Shipped through a PR and applied by the pipeline.

## Done when

`az monitor diagnostic-settings subscription list -o table` shows your setting with the
workspace, a query such as `AzureActivity | take 10` returns rows in the workspace (allow
10–15 minutes for the first events), and `./lab.sh grade` passes.
