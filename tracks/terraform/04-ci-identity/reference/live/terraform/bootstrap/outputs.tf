output "state_resource_group_name" {
  value = azurerm_resource_group.tfstate.name
}

output "state_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "state_container_name" {
  value = azurerm_storage_container.tfstate.name
}

# The three values the pipeline needs as GitHub repo variables (tf-05). None of them is a secret.
output "ci_client_id" {
  value = azurerm_user_assigned_identity.ci.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}
