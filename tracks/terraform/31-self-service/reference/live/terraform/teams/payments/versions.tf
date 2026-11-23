terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
    # The team-env module reads the team repo's IDs from GitHub's API.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-{{PREFIX}}-tfstate"
    storage_account_name = "st{{PREFIX}}tfstate{{SUFFIX}}"
    container_name       = "tfstate"
    key                  = "teams-payments.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"

  # azurerm 5.x registers no resource providers by itself (4.x registered about 60). Name the
  # ones this stack uses: a new subscription gets them registered, an old one is unaffected.
  resource_providers_to_register = [
    "Microsoft.Consumption",
    "Microsoft.ManagedIdentity",
  ]

  features {}
}
