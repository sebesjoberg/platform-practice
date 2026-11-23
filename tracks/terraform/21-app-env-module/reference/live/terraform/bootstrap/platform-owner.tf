# The platform owner (you: bootstrap is applied locally, so client_config is your own login) may
# manage secrets in every vault of the subscription. The vaults use RBAC, and being Owner of the
# subscription grants no data-plane access: without this, `./lab.sh pause` (a local destroy)
# could not delete the secrets CI wrote, and you could not read them. An Owner could grant
# themselves this role at any time anyway; writing it down makes it visible and reviewable.
resource "azurerm_role_assignment" "owner_secrets_officer" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Platform owner: break-glass access to Key Vault secrets (tf-21)."
}
