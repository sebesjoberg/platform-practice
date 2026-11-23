---
id: tf-26
title: Import a click-ops storage account
target_minutes: 20
requires: [tf-25]
---
# tf-26 Import a click-ops storage account

Day two starts with something nobody planned. Before the platform existed, a teammate created a
storage account in the portal for the finance team, who have been uploading files to it ever
since. The auditors want every resource under code review. You take it over **without
recreating it**: the files in it are real.

`./lab.sh next` printed the teammate's message. The account is `st{{PREFIX}}legacy{{SUFFIX}}` in
`rg-{{PREFIX}}-legacy`. The policy from tf-11 made them tag the group with an owner, so it has
`owner`, `env = "prod"` and `managed_by = "clickops"`.

## Deliverables

- [ ] `terraform/landing-zone` declares `rg-{{PREFIX}}-legacy` and `st{{PREFIX}}legacy{{SUFFIX}}`
      (landing-zone, because `./lab.sh pause` never destroys it: the data must outlive a pause).
      The tags follow the conventions: `owner = "{{OWNER_TAG}}"`, `env = "prod"` and
      `managed_by = "terraform"`.
- [ ] **PR 1, the import:** `import` blocks for both resources. Its plan comment for
      landing-zone says `2 to import`, nothing to add or destroy, and the only changes are the
      tags (`managed_by` becomes `terraform`). Any other change means your code doesn't describe
      the account as it is: fix the code, not Azure. Merge it; the pipeline applies.
- [ ] **PR 2, the cleanup:** delete the `import` blocks. Its plan shows `No changes.` in every
      stack.
- [ ] The plan job's trivy scan stays green. It will flag the account's open network access:
      decide whether to fix it now or accept it in `.trivyignore.yaml` with a reason (the finance
      team uploads from laptops with the account key; hardening is their next sprint).

## Done when

```bash
az group show -n rg-{{PREFIX}}-legacy --query tags
```

shows `managed_by: terraform`, the newest pipeline run on `main` is green, and `./lab.sh grade`
passes. The grader also checks that the account was never recreated (its creation time is
the one `./lab.sh next` recorded) and that `landing-zone.tfstate` holds both resources.

Target: 20 minutes.
