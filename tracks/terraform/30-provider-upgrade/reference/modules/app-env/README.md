# app-env

One environment's workload foundation, inside the spoke's resource group: the app's
user-assigned identity `id-<prefix>-app-<env>`, a Key Vault `kv-<prefix>-<env>-<suffix>` (RBAC,
7 days of soft delete, no purge protection, public network access on) with a private endpoint
`pe-kv-<prefix>-<env>` in the spoke's `snet-pe` and a DNS zone group for
`privatelink.vaultcore.azure.net`, and two role assignments on the vault: the app gets
`Key Vault Secrets User`, whoever runs Terraform gets `Key Vault Secrets Officer` and writes the
secrets in `secrets`.

The calling stack's provider block needs
`features { key_vault { purge_soft_delete_on_destroy = true } }`, so a destroyed vault is purged
and its name is free again for the next apply.

New role assignments take a while to reach the Key Vault data plane, so the module waits 120
seconds after creating them, once, before it writes secrets.

## Usage

```hcl
module "app_env" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//app-env?ref=v3.0.0"

  env                        = "dev"
  prefix                     = "acme"
  suffix                     = "abc123"
  location                   = "swedencentral"
  owner                      = "platform-team"
  resource_group_name        = module.spoke.resource_group_name
  private_endpoint_subnet_id = module.spoke.subnet_ids["pe"]
  key_vault_dns_zone_id      = data.azurerm_private_dns_zone.hub["privatelink.vaultcore.azure.net"].id

  secrets = {
    greeting = "Hello from acme dev"
  }
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
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.12, < 1.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.14, < 6.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.12, < 1.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_secret.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_private_endpoint.kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.app_secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deployer_secrets_officer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [time_sleep.rbac_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Environment: dev or prod. Part of every resource name. | `string` | n/a | yes |
| <a name="input_key_vault_dns_zone_id"></a> [key\_vault\_dns\_zone\_id](#input\_key\_vault\_dns\_zone\_id) | ID of the private DNS zone privatelink.vaultcore.azure.net (in the hub) for the endpoint's DNS zone group. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region of every resource. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Value of the owner tag on every resource. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Company prefix in every resource name (<type>-<prefix>-<env>). | `string` | n/a | yes |
| <a name="input_private_endpoint_subnet_id"></a> [private\_endpoint\_subnet\_id](#input\_private\_endpoint\_subnet\_id) | ID of the subnet that gets the vault's private endpoint (the spoke's snet-pe). | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Existing resource group for the workload resources (the spoke's rg-<prefix>-<env>). | `string` | n/a | yes |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Secrets to write into the vault, name => value. The identity running Terraform writes them (Key Vault Secrets Officer on this vault). | `map(string)` | `{}` | no |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | Random suffix that makes the Key Vault name globally unique (kv-<prefix>-<env>-<suffix>). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Client ID of the app's identity, for code that requests tokens as it. |
| <a name="output_identity_id"></a> [identity\_id](#output\_identity\_id) | Resource ID of the app's user-assigned identity (id-<prefix>-app-<env>), for identity blocks. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal (object) ID of the app's identity, for role assignments. |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | Resource ID of the vault (kv-<prefix>-<env>-<suffix>). |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | Name of the vault. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | Data plane URI of the vault (https://<name>.vault.azure.net/). |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Versionless IDs of the secrets the module wrote, by name (a reference that always gets the latest version). |
<!-- END_TF_DOCS -->
