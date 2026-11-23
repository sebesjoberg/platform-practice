---
id: tf-17
title: Test the module
target_minutes: 20
requires: [tf-16]
---
# tf-17 Test the module

Every spoke now comes from one module, so one mistake in it hits dev and prod at once. The CTO
wants the module tested on every pull request, before any plan touches a real environment, and
without Azure credentials.

## Deliverables

- [ ] `terraform/modules/spoke/tests/` with at least one `*.tftest.hcl` file that:
  - uses `mock_provider "azurerm" {}`, so nothing reaches Azure
  - has at least two `run` blocks, and every one of them has `command = plan`
  - checks the dev layout: with `prefix = "{{PREFIX}}"`, `env = "dev"` and
    `address_space = "10.1.0.0/16"` the module plans `rg-{{PREFIX}}-dev` and
    `vnet-{{PREFIX}}-dev`, the three subnet prefixes, the delegation on `snet-aca` only, and one
    DNS link per zone
  - proves that a bad input is rejected: a run with `address_space = "10.1.0.0/24"` and
    `expect_failures = [var.address_space]`
- [ ] `terraform test` passes locally in `terraform/modules/spoke`.
- [ ] The workflow's `plan` job runs `terraform test` for the module (after
      `terraform init -backend=false`), so a failing test fails the pull request. Keep exactly
      the two jobs `plan` and `apply`.
- [ ] Ship it as a PR: the plan job shows the tests passing, both env stacks plan
      `No changes.` Merge it.

## Done when

`./lab.sh grade` passes: the tests mock azurerm and only plan, one of them expects a validation
failure, the plan job runs them, and the latest pull request run is green.

Target: 20 minutes.
