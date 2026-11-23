# Same rule as the other modules: the oldest versions this module needs (>=), capped below the
# next major. The calling stack pins and locks what actually runs. hashicorp/http reads the team
# repo's IDs from GitHub's API (the federated credential's subject needs them).
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4, < 4.0"
    }
  }
}
