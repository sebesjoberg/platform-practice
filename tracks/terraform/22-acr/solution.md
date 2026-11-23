# tf-22 solution

## Approach

A new stack with a resource group and a registry; in env-dev a data source and one role
assignment. One PR. After the apply, import the image.

## Code

`terraform/shared/versions.tf`: like env-dev's, without the `time` provider and the
`key_vault` feature, with `key = "shared.tfstate"`. `terraform/shared/variables.tf`: `prefix`,
`suffix`, `location`, `owner` with the lab defaults and validations.

`terraform/shared/main.tf`:

```hcl
locals {
  tags = { owner = var.owner, env = "hub", managed_by = "terraform" }
}

resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.prefix}-shared"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "this" {
  name                = "acr${var.prefix}${var.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}
```

`terraform/env-dev/acr.tf`:

```hcl
data "azurerm_container_registry" "shared" {
  name                = "acr${var.prefix}${var.suffix}"
  resource_group_name = "rg-${var.prefix}-shared"
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = module.app_env.identity_principal_id
  principal_type       = "ServicePrincipal"
}
```

## Commands

```bash
cd "$LIVE_DIR" && git switch main && git pull && git switch -c shared-acr
# write terraform/shared/*.tf and terraform/env-dev/acr.tf
terraform -chdir=terraform/shared init -backend=false && terraform -chdir=terraform/shared validate
git add -A && git commit -m "shared stack: container registry; AcrPull for the dev app"
git push -u origin shared-acr && gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch

az acr import --name acr{{PREFIX}}{{SUFFIX}} \
  --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0
```

## Verify

```bash
az acr show -n acr{{PREFIX}}{{SUFFIX}} --query "{sku:sku.name, admin:adminUserEnabled}"
az acr repository show-tags -n acr{{PREFIX}}{{SUFFIX}} --repository hello -o tsv
./lab.sh grade
```

## Cost

ACR Basic is about 0.167 USD a day (~5 USD a month) while it exists. `./lab.sh pause`
destroys the shared stack, and `./lab.sh resume` re-imports the image into the new registry.
