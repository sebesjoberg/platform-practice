output "id" {
  description = "Resource ID of the VM."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "Name of the VM."
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip_address" {
  description = "Private IP address of the VM's NIC."
  value       = azurerm_network_interface.this.private_ip_address
}

output "public_ip_address" {
  description = "Public IP address, or null without public_ip_name."
  value       = try(azurerm_public_ip.this[0].ip_address, null)
}

output "principal_id" {
  description = "Principal ID of the system-assigned identity, or null without one."
  value       = try(azurerm_linux_virtual_machine.this.identity[0].principal_id, null)
}
