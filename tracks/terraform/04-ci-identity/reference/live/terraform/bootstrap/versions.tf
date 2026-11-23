terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }

  # Bootstrap's own state lives in the account it creates (tf-03). Entra ID only: no keys.
  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"

  # Shared key access is disabled on the state account: talk to the data plane with Entra ID.
  storage_use_azuread = true

  features {
    storage {
      # No queue_properties / static_website here, so skip the data plane checks.
      data_plane_available = false
    }
  }
}
