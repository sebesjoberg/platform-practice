# tf-26 solution

## Approach

1. Look at what exists: `az storage account show -n st{{PREFIX}}legacy{{SUFFIX}} -o jsonc`.
2. Add `variable "suffix"` to landing-zone and two `import` blocks, plan locally with
   `-generate-config-out`, and turn the generated file into `legacy.tf`.
3. **PR 1:** code plus import blocks. The plan shows `2 to import, 2 to change, 0 to destroy`
   (the tags). Merge; the pipeline imports and retags.
4. **PR 2:** delete the import blocks. Plan: `No changes.`

## Code

`terraform/landing-zone/variables.tf`, next to the others:

```hcl
variable "suffix" {
  description = "Random suffix of globally unique names (the legacy storage account, from tf-26)."
  type        = string
  default     = "{{SUFFIX}}"

  validation {
    condition     = can(regex("^[a-z0-9]{6}$", var.suffix))
    error_message = "suffix must be 6 lowercase letters or digits."
  }
}
```

`terraform/landing-zone/legacy.tf`:

```hcl
resource "azurerm_resource_group" "legacy" {
  name     = "rg-${var.prefix}-legacy"
  location = var.location
  tags     = merge(local.base_tags, { env = "prod" })
}

resource "azurerm_storage_account" "legacy" {
  name                     = "st${var.prefix}legacy${var.suffix}"
  resource_group_name      = azurerm_resource_group.legacy.name
  location                 = azurerm_resource_group.legacy.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false

  tags = merge(local.base_tags, { env = "prod" })
}
```

PR 1 only, `terraform/landing-zone/import.tf`:

```hcl
import {
  to = azurerm_resource_group.legacy
  id = "/subscriptions/{{SUBSCRIPTION_ID}}/resourceGroups/rg-{{PREFIX}}-legacy"
}

import {
  to = azurerm_storage_account.legacy
  id = "/subscriptions/{{SUBSCRIPTION_ID}}/resourceGroups/rg-{{PREFIX}}-legacy/providers/Microsoft.Storage/storageAccounts/st{{PREFIX}}legacy{{SUFFIX}}"
}
```

`.trivyignore.yaml`, one more entry (or fix the finding instead):

```yaml
  - id: AZU-0012
    paths:
      - "landing-zone/legacy.tf"
    statement: >-
      The legacy storage account (tf-26) was imported as it was found: public endpoint, default
      action Allow, because the finance team uploads from their laptops with the account key.
      Imported first, hardened later.
```

## Commands

```bash
cd "$LIVE_DIR/terraform/landing-zone"
export TF_VAR_budget_email=you@example.com   # any valid address; a local plan sends nothing
terraform init
terraform plan -generate-config-out=generated.tf
# read generated.tf, move what matters into legacy.tf, then
rm generated.tf && terraform plan            # 2 to import, 2 to change, 0 to destroy

cd "$LIVE_DIR"
git switch -c tf-26-import && git add -A && git commit -m "tf-26: import the legacy storage account"
git push -u origin tf-26-import && gh pr create --fill
gh pr checks --watch && gh pr merge --squash --delete-branch

git switch main && git pull
git switch -c tf-26-cleanup && git rm terraform/landing-zone/import.tf
git commit -m "tf-26: drop the import blocks" && git push -u origin tf-26-cleanup && gh pr create --fill
gh pr checks --watch && gh pr merge --squash --delete-branch    # plan: No changes.
```

## Verify

`az group show -n rg-{{PREFIX}}-legacy --query tags` shows `managed_by: terraform`, and
`az storage account show -n st{{PREFIX}}legacy{{SUFFIX}} --query creationTime` is unchanged.

## Cost

A Standard LRS account with a few files costs cents a month. It stays through `./lab.sh pause`;
`./lab.sh nuke` destroys it with landing-zone.
