---
id: tf-14
title: Split the landing zone into stacks
target_minutes: 25
requires: [tf-13]
---
# tf-14 Split the landing zone into stacks

One state file for everything means every plan touches everything, and a broken dev change
blocks a prod fix. From phase 3 on, dev and prod also get torn down and rebuilt on their own
(`./lab.sh pause`). The CTO wants each environment in its own stack with its own state, and
the hub shared through Azure, not through state files.

The catch: everything already exists. The move must not destroy or recreate a single resource.

This task gets 25 minutes: two new stacks and a migration in two pull requests.

## Deliverables

- [ ] New stacks `terraform/env-dev` and `terraform/env-prod`, version pins and provider as
      in landing-zone, `azurerm` backend keys `env-dev.tfstate` and `env-prod.tfstate`.
      Each declares `variable "env"`, validated to `dev` or `prod`.
- [ ] Each environment stack owns its environment's: resource group, VNet, the three
      subnets, their NSGs and associations, **both** peerings (for dev: `peer-hub-to-dev` and
      `peer-dev-to-hub`) and the two private DNS zone links (for dev: `link-vnet-{{PREFIX}}-dev`).
      Same names, CIDRs and tags as today.
- [ ] They find the hub (`vnet-{{PREFIX}}-hub`, the DNS zones in `rg-{{PREFIX}}-hub`) with
      **data sources**. No `terraform_remote_state`.
- [ ] `landing-zone` keeps the hub network, the DNS zones and their hub links, policy, budget
      and Log Analytics, and nothing of the spokes. `var.envs` goes away with them.
- [ ] **PR 1, the move:** `removed` blocks (`destroy = false`) in landing-zone and `import`
      blocks in the env stacks, in **one** PR. Its plan comment shows no destroy and no create
      in any stack. Merge it; the pipeline applies.
- [ ] **PR 2, the cleanup:** delete the `import` and `removed` blocks. Its plan shows no
      changes anywhere.

`./lab.sh next` saved the IDs of everything that moves in `~/.platform-lab/snapshots/tf-14.ids`.
They're the `id`s your import blocks need, and the grader checks that every one of them still
exists afterwards. It also recorded each spoke VNet's `resourceGuid`, which only changes when a
VNet is destroyed and recreated.

Don't run `./lab.sh pause` between PR 1 and grading: pause destroys the env stacks, resume
recreates the spokes with new `resourceGuid`s, and the "not recreated" check fails. If that
happened, `./lab.sh catchup tf-14` rebuilds the reference state and clears the baseline.

## Done when

`./lab.sh grade` passes: the three state blobs exist, each environment's state holds its VNet
(and landing-zone's only the hub), every snapshotted resource still exists, neither spoke VNet
was recreated, and no import blocks are left.
