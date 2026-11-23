---
id: tf-12
title: Budget alert
target_minutes: 20
requires: [tf-11]
---
# tf-12 Budget alert

The lab runs on a fixed monthly credit, and the CFO wants to hear about overspending before
the money is gone, not after. A subscription budget with an alert to the platform owner, in
code. Your email address must not end up in the public repo.

## Deliverables

- [ ] A GitHub **repo secret** `BUDGET_EMAIL` on `{{GH_OWNER}}/{{LIVE_REPO}}` with your
      email address. Not a repo variable: GitHub prints `env:` values in every step log, and
      the logs of a public repo are public. Only secrets are masked there.
- [ ] The workflow passes it to Terraform as `TF_VAR_budget_email` in **both** jobs (`plan`
      needs every variable just like `apply`). Keep exactly the two jobs.
- [ ] In `terraform/landing-zone`, a variable `budget_email`: no default, `sensitive = true`,
      validated as an email address.
- [ ] Action group `ag-{{PREFIX}}-budget` in `rg-{{PREFIX}}-hub` (hub tags) with one email
      receiver: `var.budget_email`.
- [ ] Subscription budget `budget-{{PREFIX}}-monthly`:
  - amount `300` (the subscription's billing currency), monthly
  - start date the first of the current month, without a diff on every later plan
  - alert at **80 %** of **actual** cost and at **100 %** of **forecasted** cost, both to
    `ag-{{PREFIX}}-budget`
- [ ] Shipped through a PR and applied by the pipeline. The plan comment must not show your
      address.

## Done when

`az consumption budget list -o table` shows `budget-{{PREFIX}}-monthly` with amount 300, the
PR plan shows `(sensitive value)` where the address would be, and `./lab.sh grade` passes.

Target: 20 minutes.
