# The product team's first service (tf-23): a Container Apps environment in the spoke's snet-aca
# and one app that runs as the app identity, pulls its image from the shared registry and reads
# one Key Vault secret.

# A workload profiles environment with only the free Consumption profile: apps scale to zero and
# cost nothing while idle. VNet integration needs snet-aca delegated to Microsoft.App/environments
# (the spoke module does that). External ingress: the app gets a public HTTPS FQDN. Its traffic
# arrives through a public IP in the infrastructure resource group Azure creates and manages
# (ME_…); that group doesn't match the owner-tag policy's rg-* pattern, so the policy leaves it
# alone.
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

  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
  }
}

resource "azurerm_container_app" "hello" {
  name                         = "ca-${var.prefix}-hello-${var.env}"
  resource_group_name          = module.spoke.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.app_env.identity_id]
  }

  # Pull with the app identity (AcrPull, tf-22): no registry password anywhere.
  registry {
    server   = data.azurerm_container_registry.shared.login_server
    identity = module.app_env.identity_id
  }

  # A Key Vault reference, not a copy: Container Apps fetches the value with the app identity
  # (Key Vault Secrets User). The versionless ID always resolves to the latest version.
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
    min_replicas = 0 # scale to zero when nobody calls
    max_replicas = 1

    container {
      name   = "hello"
      image  = "${data.azurerm_container_registry.shared.login_server}/hello:1.0"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "GREETING"
        secret_name = "greeting"
      }
    }
  }

  # A fresh AcrPull assignment needs time to propagate before the first pull. It is created
  # alongside the module's role assignments, and the app already waits for the module's secret,
  # which waits 120 s for those. depends_on makes sure the assignment exists before that.
  depends_on = [azurerm_role_assignment.app_acr_pull]
}

output "hello_url" {
  description = "Public URL of the hello app."
  value       = "https://${azurerm_container_app.hello.ingress[0].fqdn}/"
}
