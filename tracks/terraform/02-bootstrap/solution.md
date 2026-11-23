# tf-02 solution

## Approach

One small stack, `terraform/bootstrap`, applied from your workstation with local state. It
creates the state resource group, a hardened storage account and the `tfstate` container. It
also gives you a blob *data* role on the account, so tf-03 can move the state into it with
Entra ID auth.

## Code

`terraform/bootstrap/versions.tf`:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

provider "azurerm" {
  subscription_id     = "{{SUBSCRIPTION_ID}}"
  storage_use_azuread = true

  features {
    storage {
      data_plane_available = false
    }
  }
}
```

`terraform/bootstrap/state.tf` (the file name is up to you):

```hcl
data "azurerm_client_config" "current" {}

locals {
  tags = {
    owner      = "{{OWNER_TAG}}"
    env        = "platform"
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-{{PREFIX}}-tfstate"
  location = "{{LOCATION}}"
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "st{{PREFIX}}tfstate{{SUFFIX}}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id # ARM API, no account key needed
  container_access_type = "private"
}

resource "azurerm_role_assignment" "me_state_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

Outputs for the account and container names are a nice touch (the reference has
`outputs.tf`).

## Commands

```bash
cd terraform/bootstrap
terraform init
terraform fmt && terraform validate
terraform plan -out tfplan
terraform apply tfplan
terraform plan                      # "No changes."
cd ../..
git status                          # no terraform.tfstate listed (ignored)
git add terraform/bootstrap
git commit -m "bootstrap: state resource group, storage account and container"
git push
```

`.terraform.lock.hcl` may be committed or left out for now. The lab commits lock files from tf-30.

## Verify

```bash
az storage account show -g rg-{{PREFIX}}-tfstate -n st{{PREFIX}}tfstate{{SUFFIX}} \
  --query "{sharedKey:allowSharedKeyAccess, tls:minimumTlsVersion, publicBlob:allowBlobPublicAccess}"
az storage account blob-service-properties show -g rg-{{PREFIX}}-tfstate \
  --account-name st{{PREFIX}}tfstate{{SUFFIX}} --query "{versioning:isVersioningEnabled, softDelete:deleteRetentionPolicy}"
./lab.sh grade
```

## Cost

A few cents a month: an LRS account holding a handful of small state blobs. The resource
group and role assignment are free. `./lab.sh pause` keeps bootstrap; only `./lab.sh nuke`
deletes it.
