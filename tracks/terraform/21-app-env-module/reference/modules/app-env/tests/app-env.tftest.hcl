# Plan-only tests for the app-env module. mock_provider fakes azurerm and time: no credentials,
# nothing reaches Azure, and time_sleep never sleeps. The client config is overridden so the
# vault gets a tenant ID shaped like a real one.

mock_provider "azurerm" {
  override_data {
    target = data.azurerm_client_config.current
    values = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
}

mock_provider "time" {}

variables {
  env                        = "dev"
  prefix                     = "acme"
  suffix                     = "abc123"
  location                   = "swedencentral"
  owner                      = "platform-team"
  resource_group_name        = "rg-acme-dev"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-dev/providers/Microsoft.Network/virtualNetworks/vnet-acme-dev/subnets/snet-pe"
  key_vault_dns_zone_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  secrets = {
    greeting = "hello"
  }
}

run "dev_names" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.app.name == "id-acme-app-dev" && azurerm_key_vault.this.name == "kv-acme-dev-abc123" && azurerm_private_endpoint.kv.name == "pe-kv-acme-dev"
    error_message = "names must be id-<prefix>-app-<env>, kv-<prefix>-<env>-<suffix> and pe-kv-<prefix>-<env>"
  }

  assert {
    condition     = azurerm_key_vault.this.tags["owner"] == "platform-team" && azurerm_key_vault.this.tags["env"] == "dev" && azurerm_key_vault.this.tags["managed_by"] == "terraform"
    error_message = "the vault needs the owner, env and managed_by tags"
  }
}

run "vault_settings" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.soft_delete_retention_days == 7 && !azurerm_key_vault.this.purge_protection_enabled
    error_message = "the vault uses RBAC, 7 days of soft delete and no purge protection"
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled && azurerm_key_vault.this.sku_name == "standard"
    error_message = "the vault keeps public network access (CI writes secrets over it) on the standard SKU"
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == "11111111-1111-1111-1111-111111111111"
    error_message = "the vault belongs to the tenant Terraform runs in"
  }
}

run "private_endpoint" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.kv.subnet_id == var.private_endpoint_subnet_id && azurerm_private_endpoint.kv.private_service_connection[0].subresource_names[0] == "vault"
    error_message = "the endpoint goes into the given subnet and connects to the vault sub-resource"
  }

  assert {
    condition     = azurerm_private_endpoint.kv.private_dns_zone_group[0].private_dns_zone_ids[0] == var.key_vault_dns_zone_id
    error_message = "the endpoint registers itself in privatelink.vaultcore.azure.net through a DNS zone group"
  }
}

run "roles_and_secrets" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.app_secrets_user.role_definition_name == "Key Vault Secrets User" && azurerm_role_assignment.deployer_secrets_officer.role_definition_name == "Key Vault Secrets Officer"
    error_message = "the app reads secrets (Secrets User), the deployer writes them (Secrets Officer)"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_secrets_officer.principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "the deployer is whoever runs Terraform (azurerm_client_config)"
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 1 && azurerm_key_vault_secret.this["greeting"].name == "greeting"
    error_message = "one azurerm_key_vault_secret per entry in var.secrets"
  }
}

run "no_secrets" {
  command = plan

  variables {
    secrets = {}
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 0
    error_message = "secrets is optional"
  }
}

run "rejects_a_bad_suffix" {
  command = plan

  variables {
    suffix = "ABC"
  }

  expect_failures = [var.suffix]
}

run "rejects_a_zone_that_is_not_vaultcore" {
  command = plan

  variables {
    key_vault_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  expect_failures = [var.key_vault_dns_zone_id]
}
