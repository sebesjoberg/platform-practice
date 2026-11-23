output "acr_login_server" {
  description = "Registry login server, the prefix of every image name (acr<prefix><suffix>.azurecr.io)."
  value       = azurerm_container_registry.this.login_server
}
