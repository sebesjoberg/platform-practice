# tf-02 hints

Docs:
- azurerm provider: `subscription_id`, `storage_use_azuread` and the `features` block:
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs and
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/features-block
- `azurerm_storage_account`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account
- `azurerm_storage_container`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container
- Prevent Shared Key authorization: https://learn.microsoft.com/azure/storage/common/shared-key-authorization-prevent

Traps:
- **azurerm 4.x wants `subscription_id`.** Without it (or `ARM_SUBSCRIPTION_ID`) every plan
  fails with "subscription ID could not be determined". The lab puts it in the provider block
  so local runs (`./lab.sh pause`, `resume`, `nuke`) and CI behave the same.
- **Shared key off means Terraform can't use keys either.** By default the provider talks to
  the storage *data plane* with the account key. With keys disabled you get
  `KeyBasedAuthenticationNotPermitted` (403). Three things avoid it:
  - create the container with `storage_account_id` (Resource Manager API), not the
    deprecated `storage_account_name` (data plane)
  - set `storage_use_azuread = true` in the provider, so any data plane call uses Entra ID
  - set `features { storage { data_plane_available = false } }`, so the storage account resource
    skips its data plane checks (queue properties, static website), which you don't use
- **Owner is not enough for blobs.** Owner and Contributor are *control plane* roles. Reading
  and writing blobs with Entra ID needs a *data plane* role such as
  `Storage Blob Data Contributor`. You won't notice in this task. In tf-03 the backend
  fails with `AuthorizationPermissionMismatch` unless the role is there, and new role
  assignments can take a few minutes to start working. That's why the role is created now,
  one task early.
- `allow_nested_items_to_be_public = false` is the Terraform name for "no anonymous blob
  access". `min_tls_version` and `https_traffic_only_enabled` are separate arguments.
- Storage account names: 3–24 characters, lowercase letters and digits only. That's why the
  name has no dashes and uses your random suffix `{{SUFFIX}}`.
- Don't `git add .` before `.gitignore` is right. `terraform.tfstate` holds every attribute of
  every resource in plain text.
