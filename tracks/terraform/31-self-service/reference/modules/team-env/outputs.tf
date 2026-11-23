output "resource_group_name" {
  description = "The team's resource group (rg-<prefix>-<team>)."
  value       = azurerm_resource_group.this.name
}

output "identity_client_id" {
  description = "Client ID of the team's CI identity: the team's AZURE_CLIENT_ID repo variable."
  value       = azurerm_user_assigned_identity.ci.client_id
}

output "identity_principal_id" {
  description = "Principal ID of the team's CI identity, for further role assignments."
  value       = azurerm_user_assigned_identity.ci.principal_id
}

output "federated_subject" {
  description = "The OIDC subject the identity trusts: the team repo's main branch."
  value       = azurerm_federated_identity_credential.main.subject
}

output "budget_id" {
  description = "Resource ID of the team's budget."
  value       = azurerm_consumption_budget_resource_group.this.id
}
