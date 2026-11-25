---
id: tf-11
title: Azure Policy guardrails
target_minutes: 20
requires: [tf-10]
---
# tf-11 Azure Policy guardrails

Conventions in code only help for code. Someone will click a resource group together in the
portal, or deploy to the wrong region. The CTO wants guardrails Azure itself enforces: no
untagged resource groups, nothing outside Sweden Central.

There's a catch: the pipeline's identity is `Contributor`, and Contributor can't manage policy.
Granting it exactly what it needs is part of the job.

## Deliverables

- [ ] **First**, in `terraform/bootstrap` (applied **locally**, like in tf-04): a role
      assignment `Resource Policy Contributor` on the subscription for
      `id-{{PREFIX}}-github-ci`. Not Owner, not User Access Administrator: just the policy
      permissions. Commit it with the rest.
- [ ] In `terraform/landing-zone`, a custom policy definition `{{PREFIX}}-require-owner-tag`
      (mode `All`) that **denies** creating or updating a resource group whose name starts
      with rg- when it has no `owner` tag. Groups outside the naming convention (Azure's
      own, such as `NetworkWatcherRG`, or the Container Apps infrastructure group in tf-23)
      stay allowed: they can't carry your tags.
- [ ] A subscription-scope policy assignment of it, also named `{{PREFIX}}-require-owner-tag`.
- [ ] A subscription-scope assignment `{{PREFIX}}-allowed-locations` of the **built-in**
      definition *Allowed locations*, with `listOfAllowedLocations` = `["swedencentral"]`.
      Private DNS zones from tf-10 live in location `global`; find out in the built-in's rule
      whether they're affected before you decide what the list needs.
- [ ] Shipped through a PR and applied by the pipeline.

## Done when

`az group create -n rg-{{PREFIX}}-policytest -l {{LOCATION}}` (no tags) fails with
`RequestDisallowedByPolicy`, and `./lab.sh grade` passes. The grader runs the same probe and
deletes the group if it ever gets created. A new assignment can take a few minutes (rarely up
to 30) before Azure enforces it.
