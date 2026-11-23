# The jump host (tf-25): the one VM you reach from the internet, and only from your own IP. The
# Ansible track runs everything through it (ProxyJump to the web VMs), and later turns it into a
# load balancer and a self-hosted runner. It lives in the hub's snet-runner, which belongs to
# landing-zone: this stack finds the subnet and its NSG by name.

data "azurerm_subscription" "current" {}

data "azurerm_subnet" "runner" {
  name                 = "snet-runner"
  virtual_network_name = "vnet-${var.prefix}-hub"
  resource_group_name  = "rg-${var.prefix}-hub"
}

data "azurerm_network_security_group" "runner" {
  name                = "nsg-${var.prefix}-hub-runner"
  resource_group_name = "rg-${var.prefix}-hub"
}

module "jump" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//linux-vm?ref=v2.2.0"

  name                     = "vm-${var.prefix}-jump"
  resource_group_name      = azurerm_resource_group.shared.name
  location                 = azurerm_resource_group.shared.location
  subnet_id                = data.azurerm_subnet.runner.id
  ssh_public_key           = var.ssh_public_key
  public_ip_name           = "pip-${var.prefix}-jump"
  system_assigned_identity = true
  tags                     = merge(local.tags, { role = "jump", env = "hub" })
}

# SSH from your IP only. The rule lives here, next to the VM it opens, not in landing-zone with
# the NSG: `./lab.sh pause` destroys the jump VM and closes port 22 with it. landing-zone's NSG
# declares no inline rules, so a standalone rule from another stack doesn't fight it.
resource "azurerm_network_security_rule" "ssh_from_learner" {
  name                        = "allow-ssh-from-learner"
  resource_group_name         = data.azurerm_network_security_group.runner.resource_group_name
  network_security_group_name = data.azurerm_network_security_group.runner.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "${var.learner_ip}/32"
  destination_address_prefix  = data.azurerm_subnet.runner.address_prefixes[0]
  description                 = "SSH to the jump host from the learner's IP (repo variable LEARNER_IP)."
}

# The jump VM's identity reads the whole subscription: Ansible's dynamic inventory
# (azure_rm, an-02) lists VMs and their tags with it. Key Vault Secrets User on both vaults is
# granted by the env stacks, which own the vaults (they run after this stack).
resource "azurerm_role_assignment" "jump_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = module.jump.principal_id
  principal_type       = "ServicePrincipal"
}
