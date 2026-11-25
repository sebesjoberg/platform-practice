---
id: tf-27
title: Drift
target_minutes: 20
requires: [tf-26]
---
# tf-27 Drift

Your code says one thing; Azure may say another. People fix things in the portal at 2 a.m.,
scripts touch tags, a merge never gets applied. Nobody notices until something breaks. Read the
message `./lab.sh next` printed, find out what changed, and make sure the platform tells you
next time, before a teammate has to.

## Deliverables

- [ ] `.github/workflows/drift.yml`, a drift detector:
  - triggers: `schedule` (a `cron` once each weekday morning) and `workflow_dispatch`
  - plans every stack in `STACK_ORDER` with `terraform plan -detailed-exitcode` (find the
    stacks with `.github/scripts/stacks.sh`, as `terraform.yml` does); never applies
  - on exit code `2` in any stack: opens an issue labelled `drift` with the plan of each
    drifted stack, or comments on the one that is already open, and the run fails
  - when every stack is clean: closes the open `drift` issue, and the run is green
  - `permissions`: `contents: read`, `issues: write`, and the right to request an OIDC token
    (as in `terraform.yml`'s plan job); the same `env` (Azure variables, `TF_VAR_*` from
    secrets and variables, `STACK_ORDER`) as `terraform.yml`
- [ ] Merge it and run it: `gh workflow run drift.yml`. It finds drift and opens the issue.
- [ ] Reconcile. For each difference decide: put Azure back (apply the code), or change the code
      because the change was right. Then make sure nothing Terraform can't see is left behind.
- [ ] Run `drift.yml` again: green, and the issue is closed.

## Done when

The newest `drift.yml` run is green, an issue labelled `drift` exists (open or closed), the
security finding is gone from `nsg-{{PREFIX}}-dev-app`, and `./lab.sh grade` passes.
