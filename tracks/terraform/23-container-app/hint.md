# tf-23 hints

Docs:
- `azurerm_container_app_environment`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment
- `azurerm_container_app`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app
- Networking and the infrastructure subnet: https://learn.microsoft.com/azure/container-apps/networking
- Key Vault references in Container Apps secrets: https://learn.microsoft.com/azure/container-apps/manage-secrets

Traps:
- **Which environment type?** The subnet is delegated to `Microsoft.App/environments`: that's
  what a workload profiles environment wants (a Consumption-only environment wants an
  undelegated subnet). Give it one `workload_profile` named `Consumption` of type
  `Consumption`, and put the app on it with `workload_profile_name = "Consumption"`.
- **Set `infrastructure_resource_group_name`.** Azure creates that group and fills it with the
  ingress load balancer and public IP. Left unset, Azure picks a name and a later plan may want
  to replace the environment. Changing it later replaces the environment too.
- **Identity in three places.** The `identity` block attaches it to the app; `registry.identity`
  and `secret.identity` say which attached identity to use. All three take the identity's
  resource ID (`module.app_env.identity_id`), not its client or principal ID.
- **A Key Vault reference, not a value.** `key_vault_secret_id` with the versionless ID
  (`module.app_env.secret_ids["greeting"]`) makes the platform fetch the latest version. A
  `value = …` would copy the secret into the app's configuration and into Terraform's plan.
- **Permissions must exist before the first revision starts.** The pull needs `AcrPull`, the
  secret needs `Key Vault Secrets User`. The secret reference already makes Terraform wait for
  the module (and its 120 s sleep); add `depends_on` on the `AcrPull` assignment.
- **NSG rules?** None needed. With a workload profiles environment and external ingress, client
  traffic arrives through the public IP in the infrastructure group, not through your subnet's
  NSG.
- **First request is slow.** With `min_replicas = 0` the first call starts a replica; give curl
  a few seconds.
