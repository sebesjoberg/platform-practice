output "acr_login_server" {
  description = "Registry login server, the prefix of every image name (acr<prefix><suffix>.azurecr.io)."
  value       = azurerm_container_registry.this.login_server
}

output "jump_public_ip" {
  description = "Public IP of the jump VM (pip-<prefix>-jump): ssh -i ~/.ssh/<prefix>_lab azureuser@<this>."
  value       = module.jump.public_ip_address
}

output "jump_principal_id" {
  description = "Principal ID of the jump VM's system-assigned identity."
  value       = module.jump.principal_id
}
