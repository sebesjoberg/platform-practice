# tf-03 solution

## Approach

Add a backend block that points at the account from tf-02, then let `terraform init
-migrate-state` copy the local state up. Entra ID auth (`use_azuread_auth = true`) uses your
`az login` identity and the `Storage Blob Data Contributor` role you granted yourself in tf-02.

## Code

In the `terraform` block of `terraform/bootstrap/versions.tf`:

```hcl
terraform {
  # required_version / required_providers as before

  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
}
```

## Commands

```bash
cd terraform/bootstrap
terraform init -migrate-state      # "Do you want to copy existing state to the new backend?" yes
terraform plan                     # No changes. Your infrastructure matches the configuration.
rm terraform.tfstate terraform.tfstate.backup
git log --all --oneline -- '*.tfstate' '*.tfstate.*'   # must print nothing
cd ../..
git add terraform/bootstrap
git commit -m "bootstrap: store state in st{{PREFIX}}tfstate{{SUFFIX}}"
git push
```

If init fails with `AuthorizationPermissionMismatch`, your blob data role isn't active yet.
Wait a few minutes, check it with
`az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --scope "$(az storage account show -g rg-{{PREFIX}}-tfstate -n st{{PREFIX}}tfstate{{SUFFIX}} --query id -o tsv)" -o table`,
then run init again.

## Verify

```bash
az storage blob list --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} -c tfstate -o table
terraform -chdir=terraform/bootstrap state list
./lab.sh grade
```

Because versioning is on, every state write keeps the previous version as a blob version.
That's your undo button if a state file is ever corrupted (`az storage blob list
--include v ...`).

## Cost

Unchanged (cents per month).
