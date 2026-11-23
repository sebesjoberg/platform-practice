# Landing zone: the first stack the pipeline manages. More arrives from tf-07 on.

locals {
  tags = {
    owner      = "{{OWNER_TAG}}"
    env        = "hub"
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-{{PREFIX}}-hub"
  location = "{{LOCATION}}"
  tags     = local.tags
}
