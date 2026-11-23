terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14" # 5.x since tf-30: read the 5.0 upgrade guide before moving the major
    }
    # The app-env module waits for role assignments to propagate (time_sleep, tf-21).
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "env-prod.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"

  # azurerm 5.x registers no resource providers by itself (4.x registered about 60). Name the
  # ones this stack uses: a new subscription gets them registered, an old one is unaffected.
  resource_providers_to_register = [
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
  ]

  features {
    key_vault {
      # Destroying the vault (./lab.sh pause) also purges it, so the next apply can create a
      # vault with the same name. Soft delete would otherwise hold the name for 7 days.
      purge_soft_delete_on_destroy = true
    }
  }
}
