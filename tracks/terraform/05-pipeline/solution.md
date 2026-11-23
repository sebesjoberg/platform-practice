# tf-05 solution

## Approach

- `terraform/landing-zone` is an ordinary stack with its own state key.
- Workflow logic: a small `stacks` job finds every directory under `terraform/` with an
  `azurerm` backend (except `bootstrap`) and puts them in dependency order. `plan` runs on PRs
  and comments the result. `apply` runs on pushes to `main` and on manual runs.
- Identity: the managed identity from tf-04 logs in through OIDC, so no secret exists. The
  IDs are plain repo variables.

## Code

`terraform/landing-zone/versions.tf`:

```hcl
terraform {
  required_version = "~> 1.17"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "landing-zone.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"
  features {}
}
```

`terraform/landing-zone/main.tf`:

```hcl
locals {
  tags = { owner = "{{OWNER_TAG}}", env = "hub", managed_by = "terraform" }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-{{PREFIX}}-hub"
  location = "{{LOCATION}}"
  tags     = local.tags
}
```

`.github/workflows/terraform.yml` (shortened; the full file is in the reference):

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      stacks: { description: "all, or a list of stacks", default: all, type: string }

permissions:
  contents: read

env:
  ARM_USE_OIDC: "true"
  ARM_USE_AZUREAD: "true"
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
  STACK_ORDER: "landing-zone shared env-dev env-prod observability teams/payments"

jobs:
  stacks:        # grep -rl 'backend "azurerm"' terraform | dirname | minus bootstrap, ordered
    ...
  plan:
    needs: stacks
    if: github.event_name == 'pull_request'
    permissions: { contents: read, id-token: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: "1.17.2", terraform_wrapper: false }
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - run: terraform fmt -check -recursive -diff terraform
      - id: plan    # init/validate/plan each stack, build comment.md starting with "### Terraform plan"
        ...
      - if: always() && (steps.plan.outcome == 'success' || steps.plan.outcome == 'failure')
        run: gh pr comment "$PR" --repo "$GITHUB_REPOSITORY" --body-file "$RUNNER_TEMP/comment.md"
  apply:
    needs: stacks
    if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
    concurrency: { group: terraform-apply, cancel-in-progress: false }
    permissions: { contents: read, id-token: write }
    steps:   # checkout, setup-terraform, azure/login, then per stack: init + apply -auto-approve
```

Design notes:
- One `plan` job, not a matrix, so the status check is literally named `plan` (tf-06).
- The `workflow_dispatch` input reaches the script through `env:`, never through `${{ }}`
  inside `run:`.
- `apply` only runs on `main`. A manual run on another branch would present a subject that
  matches no federated credential, so it can't log in anyway.
- Applies share a concurrency group and are never cancelled half-way.
- Plans of a public repo are public. Fine here (no secrets in the plan), but remember it.

## Commands

```bash
# repo variables (not secrets)
gh variable set AZURE_CLIENT_ID --body "$(terraform -chdir=terraform/bootstrap output -raw ci_client_id)"
gh variable set AZURE_TENANT_ID --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id -o tsv)"

git switch -c pipeline
git add terraform/landing-zone .github/workflows/terraform.yml
git commit -m "Pipeline: plan on PR, apply on merge; landing-zone stack"
git push -u origin pipeline
gh pr create --fill
gh pr checks --watch            # plan runs, then the comment shows up
gh pr merge --squash --delete-branch
gh run watch                    # the apply run on main
```

## Verify

```bash
gh run list --workflow terraform.yml --branch main --limit 3
az group show -n rg-{{PREFIX}}-hub --query tags
./lab.sh grade
```

Manual run of a single stack: `gh workflow run terraform.yml -f stacks=landing-zone`.
`./lab.sh resume` uses the same dispatch with `stacks=all`.

## Cost

An empty resource group is free. GitHub Actions minutes are free for public repos.
