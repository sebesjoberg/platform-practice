# tf-23 solution

## Approach

Two resources and an output in env-dev, wired to what tf-21 and tf-22 built: the spoke's
`snet-aca`, the app identity, the vault's secret ID and the registry's login server.

## Code

`terraform/env-dev/container-app.tf`:

```hcl
locals {
  acr_login_server = "${local.acr_name}.azurecr.io" # local.acr_name is in acr.tf (tf-22)
}

resource "azurerm_container_app_environment" "this" {
  name                               = "cae-${var.prefix}-${var.env}"
  resource_group_name                = module.spoke.resource_group_name
  location                           = var.location
  infrastructure_subnet_id           = module.spoke.subnet_ids["aca"]
  infrastructure_resource_group_name = "ME_cae-${var.prefix}-${var.env}"
  internal_load_balancer_enabled     = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = { owner = var.owner, env = var.env, managed_by = "terraform" }
}

resource "azurerm_container_app" "hello" {
  name                         = "ca-${var.prefix}-hello-${var.env}"
  resource_group_name          = module.spoke.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = { owner = var.owner, env = var.env, managed_by = "terraform" }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.app_env.identity_id]
  }

  registry {
    server   = local.acr_login_server
    identity = module.app_env.identity_id
  }

  secret {
    name                = "greeting"
    key_vault_secret_id = module.app_env.secret_ids["greeting"]
    identity            = module.app_env.identity_id
  }

  ingress {
    external_enabled = true
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "hello"
      image  = "${local.acr_login_server}/hello:1.0"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "GREETING"
        secret_name = "greeting"
      }
    }
  }

  depends_on = [azurerm_role_assignment.app_acr_pull]
}

output "hello_url" {
  value = "https://${azurerm_container_app.hello.ingress[0].fqdn}/"
}
```

## Commands

```bash
cd "$LIVE_DIR" && git switch main && git pull && git switch -c hello-dev
# write terraform/env-dev/container-app.tf
terraform -chdir=terraform/env-dev init -backend=false && terraform -chdir=terraform/env-dev validate
git add -A && git commit -m "env-dev: Container Apps environment and the hello app"
git push -u origin hello-dev && gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch
```

The environment takes several minutes to create (VNet integration).

## Verify

```bash
fqdn=$(az containerapp show -g rg-{{PREFIX}}-dev -n ca-{{PREFIX}}-hello-dev --query properties.configuration.ingress.fqdn -o tsv)
curl -fsS "https://$fqdn/" | head
az containerapp show -g rg-{{PREFIX}}-dev -n ca-{{PREFIX}}-hello-dev --query "properties.configuration.secrets"
az group show -n ME_cae-{{PREFIX}}-dev --query tags      # no owner tag, and no policy denial
./lab.sh grade
```

If the revision doesn't start: `az containerapp logs show -g rg-{{PREFIX}}-dev -n ca-{{PREFIX}}-hello-dev --type system`.
A 403 on the image or the secret means a role assignment hadn't propagated yet; re-run the
workflow (`gh workflow run terraform.yml -f stacks=env-dev`).

## Cost

The Consumption profile bills only while a replica runs (scale to zero; the monthly free grant
covers a lab's traffic). Azure may bill the ingress public IP in `ME_cae-{{PREFIX}}-dev`, about
0.005 USD an hour. `./lab.sh pause` destroys env-dev and with it the environment and its
infrastructure group.
