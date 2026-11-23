# linux-vm

One Linux VM: Ubuntu 24.04 LTS (`Canonical` / `ubuntu-24_04-lts` / `server`), SSH key only
(password authentication off), one NIC `<name>-nic` in the given subnet, a Standard HDD OS
disk, and optionally a Standard static public IP and a system-assigned identity. The size
defaults to `Standard_B2ats_v2`, the lab's cheapest current x64 B-series size.

The module installs nothing inside the VM: configuration is Ansible's job. Tag the VMs
(`role`, `env`) so a dynamic inventory can group them.

## Usage

```hcl
module "jump" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//linux-vm?ref=v3.0.0"

  name                     = "vm-acme-jump"
  resource_group_name      = "rg-acme-shared"
  location                 = "swedencentral"
  subnet_id                = data.azurerm_subnet.runner.id
  ssh_public_key           = var.ssh_public_key
  public_ip_name           = "pip-acme-jump"
  system_assigned_identity = true
  tags                     = { role = "jump", env = "hub" }
}
```

The section below is generated: run
`terraform-docs markdown table --output-file README.md --output-mode inject .` in this
directory after changing an input or output.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.14, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.14, < 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_linux_virtual_machine.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_network_interface.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_public_ip.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Login user. SSH key only: password authentication is always off. | `string` | `"azureuser"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region of the VM. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | VM name (vm-<prefix>-<role>...). The NIC is <name>-nic. | `string` | n/a | yes |
| <a name="input_public_ip_name"></a> [public\_ip\_name](#input\_public\_ip\_name) | Name of a Standard, static public IP to attach (pip-<prefix>-<role>). null (the default): no public IP. | `string` | `null` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Existing resource group of the VM, its NIC, disk and public IP. | `string` | n/a | yes |
| <a name="input_size"></a> [size](#input\_size) | VM size. The lab's default is the cheapest current x64 B-series size in swedencentral (see the platform repo's README). | `string` | `"Standard_B2ats_v2"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | OpenSSH public key of admin\_username (ssh-ed25519 or ssh-rsa of at least 2048 bits). The private key never goes near Terraform. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the subnet the VM's NIC joins (it may live in another resource group). | `string` | n/a | yes |
| <a name="input_system_assigned_identity"></a> [system\_assigned\_identity](#input\_system\_assigned\_identity) | Give the VM a system-assigned managed identity (its principal\_id is an output). | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags of the VM, NIC and public IP. Inventory keys on them (role, env). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the VM. |
| <a name="output_name"></a> [name](#output\_name) | Name of the VM. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal ID of the system-assigned identity, or null without one. |
| <a name="output_private_ip_address"></a> [private\_ip\_address](#output\_private\_ip\_address) | Private IP address of the VM's NIC. |
| <a name="output_public_ip_address"></a> [public\_ip\_address](#output\_public\_ip\_address) | Public IP address, or null without public\_ip\_name. |
<!-- END_TF_DOCS -->
