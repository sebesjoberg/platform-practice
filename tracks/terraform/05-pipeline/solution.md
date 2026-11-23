# tf-05 solution

## Approach

- `terraform/landing-zone` is an ordinary stack with its own state key.
- Workflow logic: exactly two jobs. Both start with `.github/scripts/stacks.sh`, which finds
  every directory under `terraform/` with an `azurerm` backend (except `bootstrap`) and puts
  them in dependency order. `plan` runs on PRs and comments the result. `apply` runs on pushes
  to `main` and on manual runs.
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

The starter already had the triggers, permissions, checkout, setup and login. The
`TODO(tf-05)` parts become these steps (the full file is in the reference).

In job `plan`, after the `azure/login@v2` step:

```yaml
      - name: terraform fmt
        run: terraform fmt -check -recursive -diff terraform
      - name: terraform init, validate, plan
        id: plan
        env:
          STACKS: ${{ steps.stacks.outputs.list }}
        run: |
          comment="$RUNNER_TEMP/comment.md"
          echo "### Terraform plan" > "$comment"
          max=9000   # bytes of plan output per stack
          rc=0
          for s in $STACKS; do
            d="terraform/$s"; log="$RUNNER_TEMP/plan-${s//\//-}.log"
            if terraform -chdir="$d" init -input=false -no-color >"$log" 2>&1 &&
              terraform -chdir="$d" validate -no-color >>"$log" 2>&1 &&
              terraform -chdir="$d" plan -input=false -no-color -lock-timeout=5m -out=tfplan >>"$log" 2>&1; then
              summary=$(grep -m1 -E '^(Plan:|No changes\.)' "$log" || echo planned)
              terraform -chdir="$d" show -no-color tfplan >"$log.out"
            else
              rc=1; summary=FAILED; cp "$log" "$log.out"
            fi
            # append "<details><summary>$s: $summary</summary>" + the first $max bytes in a code
            # fence + "(truncated — see the run log)" when cut; cap the whole file at 60 KB
          done
          exit "$rc"
      - name: Comment the plan on the PR
        if: always() && (steps.plan.outcome == 'success' || steps.plan.outcome == 'failure')
        env:
          GH_TOKEN: ${{ github.token }}
          PR: ${{ github.event.pull_request.number }}
        run: gh pr comment "$PR" --repo "$GITHUB_REPOSITORY" --body-file "$RUNNER_TEMP/comment.md"
```

In job `apply`, after `azure/login@v2`:

```yaml
      - name: terraform apply
        env:
          STACKS: ${{ steps.stacks.outputs.list }}
        run: |
          for s in $STACKS; do
            terraform -chdir="terraform/$s" init -input=false
            terraform -chdir="terraform/$s" apply -auto-approve -input=false -lock-timeout=5m
          done
```

Design notes:
- **Exactly two jobs.** Stack discovery is a step inside each job
  (`bash .github/scripts/stacks.sh`), not a job of its own. If a separate job failed, `plan`
  would be *skipped*, and GitHub counts a skipped required check as passing (tf-06).
- **One `plan` job, not a matrix**, so the status check is literally named `plan`.
- **`stacks.sh` takes `all` or a list.** The `workflow_dispatch` input reaches it through
  `env:`, never through `${{ }}` inside `run:`. Unknown stack names fail the run.
- **Comment size.** At most 9 KB of plan per stack and 60 KB in total, far below GitHub's
  64 KB comment limit.
- **`apply` only runs on `main`.** A manual run on another branch would present a subject
  that matches no federated credential, so it can't log in anyway.
- **Applies** share a concurrency group and are never cancelled half-way.
- **Plans of a public repo are public.** Fine here (no secrets in the plan), but remember it.

## Commands

```bash
# repo variables (not secrets)
gh variable set AZURE_CLIENT_ID --body "$(terraform -chdir=terraform/bootstrap output -raw ci_client_id)"
gh variable set AZURE_TENANT_ID --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id -o tsv)"

git switch -c pipeline
git add terraform/landing-zone .github/workflows/terraform.yml .github/scripts/stacks.sh
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
