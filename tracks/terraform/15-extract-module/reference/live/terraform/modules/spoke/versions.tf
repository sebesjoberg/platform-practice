# Copied from the stacks for now, without backend and provider blocks: a module never
# configures those, it gets the provider from the stack that calls it. tf-16 revisits the pins.
terraform {
  required_version = "~> 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}
