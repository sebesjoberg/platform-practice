---
id: tf-07
title: Naming and tagging conventions
target_minutes: 15
requires: [tf-06]
---
# tf-07 Naming and tagging conventions

The landing zone is about to grow: a hub network, two spokes, DNS, policy, a budget. The CTO
has seen platforms where every engineer invents names and forgets tags, and finance can't
tell who owns what. Before anything else lands, the conventions go into code, in one place,
and bad input fails at `plan` instead of in Azure.

This is a pure refactor: Azure must not change.

## Deliverables

In `terraform/landing-zone`:

- [ ] Input variables, each with a `description`, a `type`, the lab value as `default` (CI
      has no tfvars file) and a `validation` block:

  | Variable | Type | Default | Validation |
  |---|---|---|---|
  | `prefix` | string | `"{{PREFIX}}"` | 2 to 6 lowercase letters |
  | `location` | string | `"{{LOCATION}}"` | only `swedencentral` |
  | `owner` | string | `"{{OWNER_TAG}}"` | not empty |
  | `envs` | set of strings | `["dev", "prod"]` | only `dev` and `prod` |

- [ ] A `locals` block that builds the tags from those variables: `owner = var.owner`,
      `managed_by = "terraform"` and `env`. Build one tag map per environment (`hub`, plus
      every entry of `var.envs`) so later tasks can write `local.tags["dev"]`.
- [ ] `rg-{{PREFIX}}-hub` uses them: name built from `var.prefix`, location from
      `var.location`, tags from the locals (`env = "hub"`). No hard-coded prefix, region or
      owner left in resource arguments.
- [ ] Shipped through a PR whose plan for `landing-zone` says **No changes**.

## Done when

`terraform validate` passes, the plan comment on your PR shows `landing-zone: No changes.`,
a deliberately wrong value (e.g. `terraform plan -var location=westeurope`) fails with your
error message, and `./lab.sh grade` passes.

Target: 15 minutes.
