output "resource_group_name" {
  description = "Name of the spoke's resource group (rg-<prefix>-<env>)."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the spoke VNet (vnet-<prefix>-<env>)."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs by short name: app, pe and aca."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}
