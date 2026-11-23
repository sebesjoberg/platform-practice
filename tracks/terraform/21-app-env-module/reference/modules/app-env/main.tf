# One environment's workload foundation: the app's identity and its Key Vault. The resource group
# and the subnets come from the spoke module; the calling stack passes them in.

data "azurerm_client_config" "current" {}

locals {
  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
  }
}

# The identity the app runs as (Container Apps in tf-23). Workloads get user-assigned identities:
# they outlive the app and can be granted access before the app exists.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.prefix}-app-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

# RBAC data plane (no access policies). 7 days of soft delete and no purge protection, so a
# destroyed vault can be purged and recreated under the same name (pause/resume). Public network
# access stays on: GitHub-hosted runners and WSL write secrets over it, Entra ID decides who may.
# The private endpoint below is the path from inside the VNets.
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

  # Registers kv-….privatelink.vaultcore.azure.net -> the endpoint's private IP in the hub's
  # zone. Every VNet linked to the zone then resolves the vault to that IP.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.key_vault_dns_zone_id]
  }
}

# The app reads secrets.
resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

# Whoever runs Terraform (the CI identity) writes the secrets this module manages. Its RBAC
# Administrator condition allows exactly this role among few others (bootstrap, tf-21).
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# A new role assignment takes a while to reach the Key Vault data plane. Writing a secret (or
# starting an app that reads one) right after creating the assignment fails with 403
# ForbiddenByRbac. Wait once, when the assignments are created; later applies don't sleep.
resource "time_sleep" "rbac_propagation" {
  create_duration = "120s"

  triggers = {
    app_secrets_user         = azurerm_role_assignment.app_secrets_user.id
    deployer_secrets_officer = azurerm_role_assignment.deployer_secrets_officer.id
  }
}

resource "azurerm_key_vault_secret" "this" {
  # Secret values are sensitive, their names are not: for_each may only use the names.
  for_each = nonsensitive(toset(keys(var.secrets)))

  name         = each.key
  value        = var.secrets[each.key]
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"

  depends_on = [time_sleep.rbac_propagation]
}
