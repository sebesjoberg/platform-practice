# tf-21 hints

Docs:
- `azurerm_key_vault`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault
- `azurerm_private_endpoint` (see `private_dns_zone_group`): https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint
- Key Vault RBAC roles and how long assignments take: https://learn.microsoft.com/azure/key-vault/general/rbac-guide
- `time_sleep`: https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep

Traps:
- **RBAC, not access policies.** `rbac_authorization_enabled = true` (the older name
  `enable_rbac_authorization` is deprecated in azurerm 4.x). With RBAC on, being Owner of the
  subscription gives you no access to secrets: data-plane access is its own role. That's why
  bootstrap gives you `Key Vault Secrets Officer`, and why CI needs one too.
- **403 ForbiddenByRbac right after apply.** A new role assignment takes a while to reach the
  vault. Without the `time_sleep` between the assignments and the secrets, the first apply
  fails, and so does every resume after a pause. `triggers` makes it sleep again when an
  assignment is replaced; later applies don't sleep.
- **Sensitive values can't drive `for_each`.** `var.secrets` is sensitive; loop over
  `nonsensitive(toset(keys(var.secrets)))` and look the value up with `var.secrets[each.key]`.
- **The CI condition first, then the PR.** CI assigns itself `Key Vault Secrets Officer` on the
  new vault. Its RBAC Administrator condition (bootstrap) must allow that role before the
  pipeline runs, so apply bootstrap locally before you merge, or the apply fails with
  `AuthorizationFailed`.
- **Vault names are global and outlive the vault.** A destroyed vault stays soft-deleted for 7
  days and blocks its name. `purge_soft_delete_on_destroy = true` in the stack's provider block
  purges it on destroy; if a name is stuck anyway: `az keyvault purge -n <name>`.
- **The DNS zone group is what makes the endpoint private for real.** Without it the endpoint
  has a private IP, but `kv-….vault.azure.net` still resolves to the public one inside the
  VNets.
- **Release the whole repo.** `v2.1.0` is a new minor version (a new module, nothing breaks).
  env-dev can keep spoke on `v2.0.0` and use app-env at `v2.1.0`: same spoke code either way.
- **trivy and the module.** Public network access is a CRITICAL finding (AZU-0013). It's a
  deliberate decision here, so it goes in an ignore file with the reason, scoped to the one
  file. In the platform repo the plan job's trivy would download your module and report it
  again: `--tf-exclude-downloaded-modules` leaves modules to their own repo's CI.
