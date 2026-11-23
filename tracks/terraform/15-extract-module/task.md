---
id: tf-15
title: Extract the spoke module
target_minutes: 25
requires: [tf-14]
---
# tf-15 Extract the spoke module

`env-dev` and `env-prod` are the same hundred lines twice, and every spoke change has to be
made twice. The CTO wants one `spoke` module that both stacks call. As in tf-14, everything
already exists, and the refactor must not destroy or recreate a single resource.

This task gets 25 minutes. The module is mostly cut and paste, but every resource needs a
`moved` block in both stacks, and you read two plans line by line.

## Deliverables

- [ ] A module in `terraform/modules/spoke` with everything an environment owns today: resource
      group, VNet, the three subnets, their NSGs and associations, both peerings and the two
      private DNS zone links. Same names, CIDRs and tags.
  - No `backend` and no `provider` block. A `terraform` block with the same version pins as the
    stacks, for now (tf-16 revisits them).
  - Inputs: `env`, `address_space`, `prefix`, `location`, `owner`, `hub` (an object with the
    hub's `resource_group_name`, `vnet_name` and `vnet_id`) and `private_dns_zone_names` (a set
    of zone names). The module looks nothing up itself.
- [ ] `terraform/env-dev` and `terraform/env-prod` keep their variables, backend and hub data
      sources, and call the module as `module "spoke"` with `source = "../modules/spoke"`. They
      declare no spoke resources of their own any more.
- [ ] `moved` blocks in both stacks, from each old address to its new one inside `module.spoke`
      (for example `azurerm_virtual_network.spoke` to
      `module.spoke.azurerm_virtual_network.this`). Keep them after the merge.
- [ ] `.github/scripts/stacks.sh` never lists anything under `terraform/modules/` as a stack, even
      when a module contains a `backend` block by mistake.
- [ ] **One PR.** Its plan comment shows, for both env stacks, every resource "has moved to"
      `module.spoke…` and `Plan: 0 to add, 0 to change, 0 to destroy.`; landing-zone shows no
      changes. Merge it; the pipeline applies.

`./lab.sh next` saved the IDs of every spoke resource in `~/.platform-lab/snapshots/tf-15.ids`
and each spoke VNet's `resourceGuid` in `tf-15.guids`. The grader checks that they are
unchanged. As in tf-14, don't run `./lab.sh pause` before grading.

## Done when

`./lab.sh grade` passes: the module exists and both stacks call it, the `moved` blocks are
there, stack discovery skips modules, both env states hold their VNet at `module.spoke`, and no
spoke resource was destroyed or recreated.

Target: 25 minutes.
