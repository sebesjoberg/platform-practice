# Landing zone: hub networking and the platform-wide guardrails.

locals {
  # Conventions (tf-07). Names: <type>-<prefix>-<name>, built from var.prefix.
  # Tags: every resource group carries owner, env and managed_by.
  base_tags = {
    owner      = var.owner
    managed_by = "terraform"
  }

  # One tag map per env: local.tags["hub"], local.tags["dev"], local.tags["prod"].
  tags = {
    for env in concat(["hub"], sort(var.envs)) : env => merge(local.base_tags, { env = env })
  }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.prefix}-hub"
  location = var.location
  tags     = local.tags["hub"]
}
