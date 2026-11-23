---
id: tf-03
title: Migrate bootstrap state
target_minutes: 15
requires: [tf-02]
---
# tf-03 Migrate bootstrap state

A state file on one laptop is a single point of failure, and nobody else can run the stack.
The CTO wants bootstrap's own state to live in the account bootstrap created, with Entra ID
auth only. No account keys, no SAS tokens.

## Deliverables

- [ ] `terraform/bootstrap` has an `azurerm` backend block:
  - `resource_group_name  = "rg-{{PREFIX}}-tfstate"`
  - `storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"`
  - `container_name       = "tfstate"`
  - `key                  = "bootstrap.tfstate"`
  - `use_azuread_auth     = true`
- [ ] The existing local state is migrated into that blob with `terraform init -migrate-state`.
      Don't create the resources again.
- [ ] The leftover local `terraform.tfstate` and `terraform.tfstate.backup` files are deleted
      from `terraform/bootstrap`.
- [ ] No state file was ever committed: `git log --all -- '*.tfstate' '*.tfstate.*'` is empty.
- [ ] The backend change is committed and pushed to `main`.

## Done when

`terraform plan` in `terraform/bootstrap` says "No changes" with the remote backend, the blob
`bootstrap.tfstate` shows up in the `tfstate` container, and `./lab.sh grade` passes.

Target: 15 minutes.
