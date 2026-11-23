terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
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
    key                  = "env-dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"

  features {
    key_vault {
      # Destroying the vault (./lab.sh pause) also purges it, so the next apply can create a
      # vault with the same name. Soft delete would otherwise hold the name for 7 days.
      purge_soft_delete_on_destroy = true
    }
  }
}
