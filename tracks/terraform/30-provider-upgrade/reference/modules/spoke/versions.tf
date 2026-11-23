# A module states the range it works with: the oldest versions whose features it uses (>=) and,
# for the provider, the next major version, which has breaking changes it was never written for
# (< 6.0). The stacks that call it pick the version that actually runs (~> 5.14) and lock it
# (.terraform.lock.hcl, from tf-30). A module never pins tighter than it must, or no stack could
# take a provider minor without a new module release. Moving to the next provider major is a new
# major release of this repo (v3.0.0 moved from azurerm 4.x to 5.x).
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.14, < 6.0"
    }
  }
}
