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
