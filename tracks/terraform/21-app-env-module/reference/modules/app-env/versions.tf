# Same rule as spoke: the oldest versions this module needs (>=), capped below the next major.
# hashicorp/time is still 0.x, so its cap is < 1.0. The calling stack pins what actually runs.
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81, < 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12, < 1.0"
    }
  }
}
