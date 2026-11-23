# tf-24 solution

## Approach

1. env-prod gets env-dev's module calls (minus the container app), its own variable defaults
   and the AcrPull assignment.
2. The workflow splits the apply: `apply` for everything but env-prod, `apply-prod` for env-prod
   in the `prod` environment.
3. One PR, merge, approve.

## Code

`terraform/env-prod/main.tf`:

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v2.0.0"

  env       = var.env
  vnet_cidr = var.address_space
  prefix    = var.prefix
  location  = var.location
  owner     = var.owner
  # hub and private_dns_zone_names as before
}

module "app_env" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//app-env?ref=v2.1.0"

  env                        = var.env
  prefix                     = var.prefix
  suffix                     = var.suffix
  location                   = var.location
  owner                      = var.owner
  resource_group_name        = module.spoke.resource_group_name
  private_endpoint_subnet_id = module.spoke.subnet_ids["pe"]
  key_vault_dns_zone_id      = data.azurerm_private_dns_zone.hub["privatelink.vaultcore.azure.net"].id

  secrets = {
    greeting = "Hello from ${var.prefix} ${var.env}"
  }
}
```

`terraform/env-prod/acr.tf`: the same as env-dev's. `versions.tf`: env-dev's with
`key = "env-prod.tfstate"`. `variables.tf`: add `suffix`.

`.github/workflows/terraform.yml`, the apply job's stack step and its output:

```yaml
  apply:
    # ... as before
    outputs:
      prod: ${{ steps.stacks.outputs.prod }}
    steps:
      - uses: actions/checkout@v4
      - name: Find stacks
        id: stacks
        env:
          REQUESTED: ${{ github.event_name == 'workflow_dispatch' && inputs.stacks || 'all' }}
        run: |
          list="$(bash .github/scripts/stacks.sh "$REQUESTED")"
          if [ -z "$list" ]; then echo "::error::no stacks to apply"; exit 1; fi
          rest="" prod=false
          for s in $list; do
            if [ "$s" = env-prod ]; then prod=true; else rest="$rest $s"; fi
          done
          echo "list=${rest# }" >> "$GITHUB_OUTPUT"
          echo "prod=$prod" >> "$GITHUB_OUTPUT"
      # setup-terraform, azure/login and the apply loop as before
```

The new job:

```yaml
  apply-prod:
    needs: apply
    if: needs.apply.outputs.prod == 'true'
    runs-on: ubuntu-latest
    environment: prod
    concurrency:
      group: terraform-apply-prod
      cancel-in-progress: false
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
          terraform_wrapper: false
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - name: terraform apply env-prod
        run: |
          terraform -chdir=terraform/env-prod init -input=false
          terraform -chdir=terraform/env-prod apply -auto-approve -input=false -lock-timeout=5m
```

## Commands

```bash
cd "$LIVE_DIR" && git switch main && git pull && git switch -c prod
# edit terraform/env-prod and the workflow
terraform -chdir=terraform/env-prod init -backend=false && terraform -chdir=terraform/env-prod validate
git add -A && git commit -m "prod: spoke v2.0.0, app-env v2.1.0; gated apply-prod job"
git push -u origin prod && gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch
gh run watch          # apply finishes, then apply-prod waits: approve it in the browser
```

Or approve from the terminal (you're the required reviewer):

```bash
run=$(gh run list --workflow terraform.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
env_id=$(gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runs/$run/pending_deployments --jq '.[0].environment.id')
gh api -X POST repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runs/$run/pending_deployments \
  -F "environment_ids[]=$env_id" -f state=approved -f comment="prod: app-env"
```

## Verify

```bash
gh api "repos/{{GH_OWNER}}/{{LIVE_REPO}}/deployments?environment=prod&per_page=1" --jq '.[0] | {id, sha, created_at}'
az keyvault show -n kv-{{PREFIX}}-prod-{{SUFFIX}} --query properties.enableRbacAuthorization
./lab.sh grade
```

## Cost

A second Key Vault (cents) and a second private endpoint (~7 USD a month while it exists).
`./lab.sh pause` destroys env-prod.
