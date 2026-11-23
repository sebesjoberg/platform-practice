---
id: tf-05
title: Plan on PR, apply on merge
target_minutes: 20
requires: [tf-04]
---
# tf-05 Plan on PR, apply on merge

From now on nobody runs `terraform apply` on their laptop for the platform. The CTO wants
every change reviewed as a pull request with its plan attached, and applied by the pipeline
once merged. The first stack the pipeline owns is a tiny landing zone.

## Deliverables

- [ ] A new stack `terraform/landing-zone`:
  - same version pins and provider convention as bootstrap
  - `azurerm` backend in the same account and container with key `landing-zone.tfstate` and
    `use_azuread_auth = true`
  - one resource group `rg-{{PREFIX}}-hub` in `{{LOCATION}}` with the tags
    `owner = "{{OWNER_TAG}}"`, `env = "hub"`, `managed_by = "terraform"`
- [ ] Repo **variables** (not secrets) on `{{GH_OWNER}}/{{LIVE_REPO}}`: `AZURE_CLIENT_ID` (the
      client ID of `id-{{PREFIX}}-github-ci`), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. No repo
      secrets named `ARM_*` or `AZURE_CLIENT_SECRET`.
- [ ] Workflow `.github/workflows/terraform.yml`:
  - runs on `pull_request` to `main`, on `push` to `main`, and on `workflow_dispatch` with an
    input `stacks` (default `all`)
  - the stacks are every directory under `terraform/` except `bootstrap`, found when the
    workflow runs, so a new stack needs no workflow change
  - a job named exactly `plan` (pull requests): `terraform fmt -check`, `init`, `validate`
    and `plan` for every stack. It posts the plan as a PR comment whose body starts with
    `### Terraform plan`.
  - a job named exactly `apply` (push to `main` and manual runs): `init` and
    `apply -auto-approve` for every selected stack
  - Azure login with OIDC through `azure/login@v2`; the workflow grants the id-token: write
    permission and sets `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true` and the `ARM_*_ID`
    values from the repo variables. No client secret anywhere.
- [ ] Ship it the way all future changes ship: open a PR with the stack and the workflow,
      read the plan comment, merge, and watch the `apply` run on `main` create
      `rg-{{PREFIX}}-hub`.

## Done when

The PR shows a `### Terraform plan` comment, the latest `terraform` run on `main` is green,
`az group show -n rg-{{PREFIX}}-hub` works, and `./lab.sh grade` passes.

Target: 20 minutes.
