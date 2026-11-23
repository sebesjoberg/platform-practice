# tf-03 hints

Docs:
- azurerm backend, Microsoft Entra ID section: https://developer.hashicorp.com/terraform/language/backend/azurerm
- Changing backends and `-migrate-state`: https://developer.hashicorp.com/terraform/cli/commands/init#backend-initialization
- Authorize blob access with Entra ID: https://learn.microsoft.com/azure/storage/blobs/authorize-access-azure-active-directory

Traps:
- **Without `use_azuread_auth = true` the backend asks for the account key** (it calls
  listKeys). With shared keys disabled that ends in `KeyBasedAuthenticationNotPermitted`.
- **`AuthorizationPermissionMismatch` (403)** means your user has no blob *data* role on the
  account, or it was granted only minutes ago. Check the `Storage Blob Data Contributor`
  assignment from tf-02, wait a few minutes and run `terraform init -migrate-state` again.
  Subscription Owner does not give data plane access.
- **The backend block can't use variables or locals.** Write the literal names, or pass them
  with `-backend-config`.
- Locally the backend gets the tenant from your `az login` session. In CI it comes from
  `ARM_TENANT_ID` (tf-05).
- Answer `yes` when init asks to copy the existing state. Afterwards Terraform leaves the old
  local files in place. They're now stale and dangerous, so delete them.
- `git log --all` also covers branches you have since deleted locally but still have on
  origin. If a state file was ever committed, rewriting history is the only cleanup, and
  every secret in it must be treated as leaked.
