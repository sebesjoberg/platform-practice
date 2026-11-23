output "identity_id" {
  description = "Resource ID of the app's user-assigned identity (id-<prefix>-app-<env>), for identity blocks."
  value       = azurerm_user_assigned_identity.app.id
}

output "identity_principal_id" {
  description = "Principal (object) ID of the app's identity, for role assignments."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "identity_client_id" {
  description = "Client ID of the app's identity, for code that requests tokens as it."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "key_vault_id" {
  description = "Resource ID of the vault (kv-<prefix>-<env>-<suffix>)."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Name of the vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Data plane URI of the vault (https://<name>.vault.azure.net/)."
  value       = azurerm_key_vault.this.vault_uri
}

output "secret_ids" {
  description = "Versionless IDs of the secrets the module wrote, by name (a reference that always gets the latest version)."
  value       = { for name, s in azurerm_key_vault_secret.this : name => s.versionless_id }
}
