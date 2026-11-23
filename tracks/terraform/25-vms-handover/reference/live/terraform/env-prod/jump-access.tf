# The jump VM (shared stack, tf-25) reads this environment's secrets: the Ansible track fetches
# them with the VM's managed identity (an-07). The vault's owner, this stack, grants the access.
# shared runs before the env stacks, so the VM and its identity exist when this applies.
data "azurerm_virtual_machine" "jump" {
  name                = "vm-${var.prefix}-jump"
  resource_group_name = "rg-${var.prefix}-shared"
}

resource "azurerm_role_assignment" "jump_secrets_user" {
  scope                = module.app_env.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_virtual_machine.jump.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
