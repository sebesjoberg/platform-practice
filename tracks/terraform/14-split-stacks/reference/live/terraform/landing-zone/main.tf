# Landing zone: the hub network and the platform-wide guardrails. The spokes live in their own
# stacks (terraform/env-dev, terraform/env-prod) since tf-14.

locals {
  # Conventions (tf-07). Names: <type>-<prefix>-<name>, built from var.prefix.
  # Tags: every resource group carries owner, env and managed_by.
  base_tags = {
    owner      = var.owner
    managed_by = "terraform"
  }

  tags = {
    hub = merge(local.base_tags, { env = "hub" })
  }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.prefix}-hub"
  location = var.location
  tags     = local.tags["hub"]
}
