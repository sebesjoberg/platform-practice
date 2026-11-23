terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "observability.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"
  features {}
}
