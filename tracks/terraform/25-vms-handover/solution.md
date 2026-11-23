# tf-25 solution

## Approach

1. Modules repo: `linux-vm/main.tf` against the starter, README, changelog; merge; tag
   `v2.2.0`.
2. Repo variables `LEARNER_IP` and `SSH_PUBLIC_KEY`, and the two `TF_VAR_*` lines in the
   workflow.
3. One PR: the jump VM, its SSH rule and Reader role in `shared`; the web VMs in env-dev; Key
   Vault access for the jump VM in both env stacks.

## Code

`linux-vm/main.tf` (modules repo):

```hcl
resource "azurerm_public_ip" "this" {
  count = var.public_ip_name == null ? 0 : 1

  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(azurerm_public_ip.this[0].id, null)
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.size
  tags                            = var.tags
  network_interface_ids           = [azurerm_network_interface.this.id]
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  dynamic "identity" {
    for_each = var.system_assigned_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
}
```

`terraform/shared/jump.tf`:

```hcl
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
}

resource "azurerm_role_assignment" "jump_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = module.jump.principal_id
  principal_type       = "ServicePrincipal"
}

output "jump_public_ip" {
  value = module.jump.public_ip_address
}
```

`terraform/shared/variables.tf` adds:

```hcl
variable "learner_ip" {
  type      = string
  sensitive = true

  validation {
    condition     = can(cidrhost("${var.learner_ip}/32", 0)) && can(regex("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", var.learner_ip))
    error_message = "learner_ip must be one IPv4 address (set the GitHub variable LEARNER_IP)."
  }
}

variable "ssh_public_key" {
  type = string
  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}
```

`terraform/env-dev/web.tf` (and `variable "ssh_public_key"` in env-dev):

```hcl
module "web" {
  source   = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//linux-vm?ref=v2.2.0"
  for_each = toset(["1", "2"])

  name                = "vm-${var.prefix}-web-${var.env}-${each.key}"
  resource_group_name = module.spoke.resource_group_name
  location            = var.location
  subnet_id           = module.spoke.subnet_ids["app"]
  ssh_public_key      = var.ssh_public_key
  tags                = { owner = var.owner, env = var.env, managed_by = "terraform", role = "web" }
}

output "web_private_ips" {
  value = [for k in sort(keys(module.web)) : module.web[k].private_ip_address]
}
```

`terraform/env-dev/jump-access.tf` and `terraform/env-prod/jump-access.tf`:

```hcl
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
```

Workflow env:

```yaml
  TF_VAR_learner_ip: ${{ vars.LEARNER_IP }}
  TF_VAR_ssh_public_key: ${{ vars.SSH_PUBLIC_KEY }}
```

## Commands

```bash
gh variable set LEARNER_IP -R {{GH_OWNER}}/{{LIVE_REPO}} --body {{LEARNER_IP}}
gh variable set SSH_PUBLIC_KEY -R {{GH_OWNER}}/{{LIVE_REPO}} < ~/.ssh/{{PREFIX}}_lab.pub

cd "$MODULES_DIR" && git switch main && git pull && git switch -c linux-vm
# write linux-vm/main.tf; README (terraform-docs), CHANGELOG.md, README.md
(cd linux-vm && terraform init -backend=false && terraform test)
git add -A && git commit -m "linux-vm module (2.2.0)" && git push -u origin linux-vm
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull && git tag -a v2.2.0 -m "linux-vm" && git push origin v2.2.0

cd "$LIVE_DIR" && git switch main && git pull && git switch -c vms
# edit terraform/shared, terraform/env-dev, terraform/env-prod, the workflow
git add -A && git commit -m "VMs: jump host and two web servers (linux-vm v2.2.0)"
git push -u origin vms && gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch    # approve apply-prod
```

## Verify

```bash
cd "$LIVE_DIR"
terraform -chdir=terraform/shared init >/dev/null && jump=$(terraform -chdir=terraform/shared output -raw jump_public_ip)
terraform -chdir=terraform/env-dev init >/dev/null && web=$(terraform -chdir=terraform/env-dev output -json web_private_ips | jq -r '.[0]')
key=~/.ssh/{{PREFIX}}_lab
ssh -i $key azureuser@$jump 'hostname; lsb_release -ds'
ssh -i $key -o "ProxyCommand=ssh -i $key -W %h:%p azureuser@$jump" azureuser@$web \
  'curl -fsS -o /dev/null http://archive.ubuntu.com/ubuntu/ && echo apt reachable'
./lab.sh grade
```

`terraform output` needs the backend (no `-backend=false`) and your `az login`.

## Cost

| What | USD/hour |
|---|---|
| 3 × `Standard_B2ats_v2` | 0.029 |
| 3 × Standard HDD OS disk (30 GiB) | ~0.006 |
| `pip-{{PREFIX}}-jump` (Standard, static) | 0.005 |
| Web VMs' internet access (default outbound access) | 0 |

About 0.04 USD an hour (~0.4 kr) on top of what ran before. A NAT gateway for the web subnet
(0.045 USD an hour plus data) would cost more than all three VMs, so the lab doesn't use one.
Run `./lab.sh pause` whenever you stop.
