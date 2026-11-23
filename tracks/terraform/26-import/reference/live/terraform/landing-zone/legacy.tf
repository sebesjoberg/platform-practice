# A storage account a teammate created by hand in the portal, before the platform existed
# (tf-26). It was imported, not recreated: the files in it are the finance team's. It lives in
# landing-zone, the stack that ./lab.sh pause never destroys, so the data outlives a pause.
#
# The code describes the account exactly as it was found (every argument where the provider's
# default differs from what the portal and az chose), so the first plan after the import only
# changed the managed_by tag. Hardening it (network rules, shared keys off) is a follow-up with
# the finance team: their upload scripts use the account key today.

resource "azurerm_resource_group" "legacy" {
  name     = "rg-${var.prefix}-legacy"
  location = var.location
  tags     = merge(local.base_tags, { env = "prod" })
}

resource "azurerm_storage_account" "legacy" {
  name                     = "st${var.prefix}legacy${var.suffix}"
  resource_group_name      = azurerm_resource_group.legacy.name
  location                 = azurerm_resource_group.legacy.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false # azurerm's default is true; the account was created without public blob access
  cross_tenant_replication_enabled = false

  tags = merge(local.base_tags, { env = "prod" })
}
