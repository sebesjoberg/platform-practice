# tf-21 solution

## Approach

1. Modules repo: copy the starters, write `app-env/main.tf` against the starter's variables,
   outputs and tests; README, changelog; merge; tag `v2.1.0`.
2. Platform repo: extend bootstrap (one GUID, plus the starter's `platform-owner.tf`) and apply
   it locally; then one PR with the env-dev module call, the provider feature and the trivy
   flag.

## Code

`app-env/main.tf` (modules repo):

```hcl
data "azurerm_client_config" "current" {}

locals {
  tags = { owner = var.owner, env = var.env, managed_by = "terraform" }
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.prefix}-app-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_key_vault" "this" {
  name                = "kv-${var.prefix}-${var.env}-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = true
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${var.prefix}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "pe-kv-${var.prefix}-${var.env}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.key_vault_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_propagation" {
  create_duration = "120s"
  triggers = {
    app_secrets_user         = azurerm_role_assignment.app_secrets_user.id
    deployer_secrets_officer = azurerm_role_assignment.deployer_secrets_officer.id
  }
}

resource "azurerm_key_vault_secret" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  name         = each.key
  value        = var.secrets[each.key]
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"

  depends_on = [time_sleep.rbac_propagation]
}
```

From the starter, `.trivyignore.yaml` (modules repo root) and the CI line:

```yaml
misconfigurations:
  - id: AZU-0013
    paths:
      - "app-env/main.tf"
    statement: >-
      Public network access is a platform decision: GitHub-hosted runners and WSL write secrets
      over it. Data plane is RBAC only; the private endpoint serves the VNets.
```

```yaml
"$RUNNER_TEMP/bin/trivy" config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml .
```

`terraform/bootstrap/identity.tf`: one more entry in `ci_assignable_roles`
(`key_vault_secrets_officer = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"`). From the starter,
`terraform/bootstrap/platform-owner.tf`:

```hcl
resource "azurerm_role_assignment" "owner_secrets_officer" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

`terraform/env-dev/main.tf` (below `module "spoke"`):

```hcl
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

`terraform/env-dev/versions.tf`: `time = { source = "hashicorp/time", version = "~> 0.14" }` in
`required_providers`, and in the provider block:

```hcl
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
```

`terraform/env-dev/variables.tf`: `variable "suffix"` with default `"{{SUFFIX}}"` and a
`^[a-z0-9]{6}$` validation. In `.github/workflows/terraform.yml`, the trivy line gets
`--tf-exclude-downloaded-modules`.

## Commands

```bash
s=~/.platform-lab/starter/tf-21
cd "$MODULES_DIR" && git switch main && git pull && git switch -c app-env
cp -rn $s/modules/app-env . && cp $s/modules/.trivyignore.yaml . && cp $s/modules/.github/workflows/ci.yml .github/workflows/
# write app-env/main.tf; edit CHANGELOG.md, README.md
(cd app-env && terraform init -backend=false && terraform test &&
  terraform-docs markdown table --output-file README.md --output-mode inject .)
git add -A && git commit -m "app-env module (2.1.0)" && git push -u origin app-env
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull && git tag -a v2.1.0 -m "app-env" && git push origin v2.1.0

cd "$LIVE_DIR" && git switch main && git pull && git switch -c app-env-dev
cp -n $s/live/terraform/bootstrap/platform-owner.tf terraform/bootstrap/
# edit terraform/bootstrap/identity.tf, terraform/env-dev, the workflow
terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap apply
git add -A && git commit -m "env-dev: app identity and Key Vault (app-env v2.1.0)"
git push -u origin app-env-dev && gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch
```

The env-dev apply takes two minutes longer than usual the first time: that's the `time_sleep`.

## Verify

```bash
az keyvault show -n kv-{{PREFIX}}-dev-{{SUFFIX}} --query "properties.{rbac:enableRbacAuthorization, days:softDeleteRetentionInDays, purge:enablePurgeProtection, public:publicNetworkAccess}"
az network private-endpoint dns-zone-group list -g rg-{{PREFIX}}-dev --endpoint-name pe-kv-{{PREFIX}}-dev -o table
az keyvault secret show --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n greeting --query value -o tsv
./lab.sh grade
```

## Cost

Key Vault standard bills per operation (cents a month here). The private endpoint costs about
0.01 USD per hour (~7 USD a month) while it exists; `./lab.sh pause` destroys env-dev and with
it the endpoint.
