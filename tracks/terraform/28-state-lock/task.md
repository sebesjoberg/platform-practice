---
id: tf-28
title: A stuck state lock
target_minutes: 15
requires: [tf-27]
---
# tf-28 A stuck state lock

Read the message `./lab.sh next` printed. Every Terraform run on `env-dev` now stops before it
starts, in CI and on your machine. Nothing is broken in Azure. Something is wrong with how
Terraform makes sure two runs never write the same state at once.

Unlocking a state that a running apply still holds is how states get corrupted. So the order of
this task matters: first prove that nobody holds the lock for a reason, then remove it.

## Deliverables

- [ ] Reproduce it locally: `terraform plan` in `terraform/env-dev`. Note the lock's **ID**, who
      took it, when, and for which operation.
- [ ] Prove the lock is stale: no pipeline run is in progress (`gh run list --status in_progress`,
      and the drift workflow too), and the blob's lease tells the same story
      (`az storage blob show --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} -c tfstate -n env-dev.tfstate --query properties.lease`).
- [ ] Release it with `terraform force-unlock <ID>` from `terraform/env-dev`.
- [ ] Show that `env-dev` plans and applies in CI again:
      `gh workflow run terraform.yml -f stacks=env-dev`, and the run is green.

## Done when

The lease on `env-dev.tfstate` is no longer held, a pipeline run that started after the incident
is green, and `./lab.sh grade` passes.

Target: 15 minutes.
