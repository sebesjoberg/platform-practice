---
id: tf-05
title: Plan on PR, apply on merge
target_minutes: 25
requires: [tf-04]
---
# tf-05 Plan on PR, apply on merge

From now on nobody runs `terraform apply` on their laptop for the platform. The CTO wants
every change reviewed as a pull request with its plan attached, and applied by the pipeline
once merged. The first stack the pipeline owns is a tiny landing zone.

`./lab.sh next` has put two starter files into your repo (it never overwrites existing ones):

- `.github/workflows/terraform.yml` already has:
  - the triggers: `pull_request` to `main`, `push` to `main`, and `workflow_dispatch` with
    input `stacks`, default `all`
  - the two jobs `plan` and `apply` with their per-job permissions
  - checkout, `hashicorp/setup-terraform` and the OIDC login through `azure/login@v2`
  - the `ARM_*` environment
  - `# TODO(tf-05)` markers where the real work goes
- `.github/scripts/stacks.sh` prints the stacks to run: every directory under `terraform/` with
  an `azurerm` backend except `bootstrap`, in dependency order. A new stack needs no workflow
  change. Both jobs call it first.

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
- [ ] Every `TODO(tf-05)` in the workflow is done, and the markers are removed:
  - job `plan` (pull requests): `terraform fmt -check` over `terraform/`, then `init`,
    `validate` and `plan` for every stack. It posts **one** PR comment whose body starts
    with `### Terraform plan` and holds each stack's plan, even when a plan fails. Truncate
    long plans to stay below GitHub's 64 KB comment limit.
  - job `apply` (push to `main` and manual runs): `init` and `apply -auto-approve` for every
    selected stack, in order
  - keep exactly the two jobs `plan` and `apply`, and no client secret anywhere
- [ ] Ship it the way all future changes ship: open a PR with the stack, the workflow and
      `.github/scripts/stacks.sh`, read the plan comment, merge, and watch the `apply` run on
      `main` create `rg-{{PREFIX}}-hub`.

## Done when

The PR shows a `### Terraform plan` comment, the latest `terraform` run on `main` is green,
`az group show -n rg-{{PREFIX}}-hub` works, and `./lab.sh grade` passes.

Target: 25 minutes.
