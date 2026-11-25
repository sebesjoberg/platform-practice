---
id: tf-02
title: Bootstrap stack
target_minutes: 20
requires: [tf-01]
---
# tf-02 Bootstrap stack

Terraform needs somewhere safe to keep its state before it can manage anything else. The CTO
wants a dedicated, locked-down storage account for state, built with Terraform itself.
The usual chicken-and-egg answer: a small `bootstrap` stack that starts with **local** state.
You move that state into the account in tf-03.

## Deliverables

All code lives in `terraform/bootstrap/` in your repo.

- [ ] A `terraform` block with `required_version = "~> 1.17"` and the `hashicorp/azurerm`
      provider pinned to `~> 4.81`.
- [ ] An `azurerm` provider block that sets `subscription_id = "{{SUBSCRIPTION_ID}}"`
      (lab convention, see `tracks/terraform/README.md`).
- [ ] Resource group `rg-{{PREFIX}}-tfstate` in `{{LOCATION}}` with the tags
      `owner = "{{OWNER_TAG}}"`, `env = "platform"`, `managed_by = "terraform"`.
- [ ] Storage account `st{{PREFIX}}tfstate{{SUFFIX}}` in that group, with the same tags:
  - `Standard` tier, `LRS` replication, kind `StorageV2`
  - minimum TLS version `TLS1_2`, HTTPS only
  - no public (anonymous) blob access
  - **shared key access disabled**. Only Microsoft Entra ID auth is allowed.
  - blob versioning on, blob soft delete 7 days, container soft delete 7 days
- [ ] A private blob container `tfstate` in the account.
- [ ] A role assignment that gives **you** (the identity running Terraform, found through the
      `azurerm_client_config` data source) `Storage Blob Data Contributor` on the storage
      account. Without it you can't read or write state blobs once shared keys are off.
- [ ] Local state only for now: no `backend` block yet. `terraform apply` has run.
- [ ] The code is committed and pushed to `main`. The state file is **not** committed.

## Done when

`terraform plan` in `terraform/bootstrap` shows no changes, `git status` shows no
`terraform.tfstate`, and `./lab.sh grade` passes.
