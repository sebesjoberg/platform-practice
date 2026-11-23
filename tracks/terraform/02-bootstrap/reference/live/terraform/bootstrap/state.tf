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
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Data plane access for whoever runs Terraform locally (control plane Owner is not enough).
resource "azurerm_role_assignment" "me_state_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
