# A module states the range it works with: the oldest versions whose features it uses (>=) and,
# for the provider, the next major version, which has breaking changes it was never written for
# (< 5.0). The stacks that call it pick the version that actually runs: ~> 4.81 now, a lock file
# from tf-30. A module never pins tighter than it must, or no stack could upgrade without a new
# module release.
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81, < 5.0"
    }
  }
}
