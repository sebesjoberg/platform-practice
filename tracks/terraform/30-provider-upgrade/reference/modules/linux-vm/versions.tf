# Same rule as the other modules: the oldest versions this module needs (>=), capped below the
# next major. The calling stack pins what actually runs.
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
  }
}
