---
id: tf-29
title: Move monitoring into its own stack
target_minutes: 25
requires: [tf-28]
---
# tf-29 Move monitoring into its own stack

The platform team is growing, and monitoring gets an owner of its own. Every landing-zone change
plans the Log Analytics workspace too, and a policy tweak should never be able to touch the
platform's logs. The CTO wants monitoring in its own stack, `observability`, with its own state.

The catch, again: the workspace exists and holds the logs. Destroying it would lose them, and a
new workspace gets a new workspace ID (`customerId`) that every agent and query would need.
Nothing may be destroyed or recreated.

This task gets 25 minutes: a new stack and a migration in two pull requests.

## Deliverables

- [ ] A new stack `terraform/observability`: backend key `observability.tfstate`, pins and
      provider as in the other stacks, validated variables with the lab values as defaults.
- [ ] It owns `law-{{PREFIX}}-platform` (still in `rg-{{PREFIX}}-hub`, found by name; same SKU,
      retention, 0.1 GB cap and tags) and the subscription diagnostic setting
      `activity-log-to-law` that streams the Activity Log into it.
- [ ] `landing-zone` keeps everything else and declares neither of the two any more.
- [ ] **PR 1, the move:** `removed` blocks (`destroy = false`) in landing-zone and `import`
      blocks in observability, in **one** PR. Its plan comment shows no destroy and no create in
      any stack. Merge it; the pipeline applies.
- [ ] **PR 2, the cleanup:** delete the `import` and `removed` blocks. Its plan shows no changes
      anywhere.

`./lab.sh next` saved both IDs in `~/.platform-lab/snapshots/tf-29.ids` and the workspace's
`customerId` in `~/.platform-lab/snapshots/tf-29.guids`. The grader checks that the ID still
exists and the `customerId` didn't change. Like landing-zone, `observability` survives
`./lab.sh pause`, so pausing doesn't affect the move.

## Done when

`./lab.sh grade` passes: the workspace is in `observability.tfstate` and not in
`landing-zone.tfstate`, its ID and `customerId` are unchanged, the Activity Log still flows into
it, and no import or removed blocks are left.

Target: 25 minutes.
