# spoke

One environment's spoke network: resource group `rg-<prefix>-<env>`, VNet `vnet-<prefix>-<env>`
with the subnets `snet-app` (x.1.0/24), `snet-pe` (x.2.0/24) and `snet-aca` (x.4.0/23,
delegated to `Microsoft.App/environments`), one NSG per subnet, both peerings with the hub and
links to the hub's private DNS zones.

The module looks nothing up: the calling stack passes the hub in. Pin a release tag in
`?ref=`; see the repository README for how versions work.

## Usage

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v2.0.0"

  env       = "dev"
  vnet_cidr = "10.1.0.0/16"
  prefix    = "acme"
  location  = "swedencentral"
  owner     = "platform-team"

  hub = {
    resource_group_name = data.azurerm_resource_group.hub.name
    vnet_name           = data.azurerm_virtual_network.hub.name
    vnet_id             = data.azurerm_virtual_network.hub.id
  }
  private_dns_zone_names = keys(data.azurerm_private_dns_zone.hub)
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
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.81, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.81, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_security_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_private_dns_zone_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [azurerm_virtual_network_peering.hub_to_spoke](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |
| [azurerm_virtual_network_peering.spoke_to_hub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Environment of the spoke: dev or prod. Part of every resource name and the env tag. | `string` | n/a | yes |
| <a name="input_hub"></a> [hub](#input\_hub) | The hub VNet the spoke peers with: its resource group (which also holds the private DNS zones), name and ID. | <pre>object({<br/>    resource_group_name = string<br/>    vnet_name           = string<br/>    vnet_id             = string<br/>  })</pre> | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region of the resource group, VNet and NSGs. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Value of the owner tag on the resource group and every taggable resource. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Company prefix in every resource name (<type>-<prefix>-<env>). | `string` | n/a | yes |
| <a name="input_private_dns_zone_names"></a> [private\_dns\_zone\_names](#input\_private\_dns\_zone\_names) | Private DNS zones in the hub resource group to link the spoke VNet to (privatelink.* zones). | `set(string)` | n/a | yes |
| <a name="input_vnet_cidr"></a> [vnet\_cidr](#input\_vnet\_cidr) | CIDR block of the spoke VNet, one /16; the subnets are cut out of it: snet-app x.1.0/24, snet-pe x.2.0/24, snet-aca x.4.0/23. Called address\_space before v2.0.0. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the spoke's resource group (rg-<prefix>-<env>). |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Subnet IDs by short name: app, pe and aca. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | ID of the spoke VNet. |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | Name of the spoke VNet (vnet-<prefix>-<env>). |
<!-- END_TF_DOCS -->
