# Guardrails (tf-11): Azure Policy at subscription scope, enforced on every create and update.

data "azurerm_subscription" "current" {}

# Built-in "Allowed locations" (Indexed mode). Its rule skips resources whose location is
# "global" (private DNS zones and links, action groups), so the list holds only the region.
data "azurerm_policy_definition" "allowed_locations" {
  name = "e56962a6-4747-49cd-b67b-bf8b01975c4c"
}

# Resource groups following our naming convention (rg-*) must carry an owner tag. Groups Azure
# creates for itself (NetworkWatcherRG, the Container Apps infrastructure group in tf-23) can't
# carry our tags, so the rule leaves names outside the convention alone.
resource "azurerm_policy_definition" "require_owner_tag" {
  name         = "${var.prefix}-require-owner-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require an owner tag on rg-* resource groups"
  description  = "Denies creating or updating a resource group named rg-* without an owner tag."

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { field = "name", like = "rg-*" },
        { field = "tags['owner']", exists = "false" },
      ]
    }
    then = { effect = "deny" }
  })
}

resource "azurerm_subscription_policy_assignment" "require_owner_tag" {
  name                 = "${var.prefix}-require-owner-tag"
  display_name         = "Require an owner tag on rg-* resource groups"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.require_owner_tag.id
}

resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "${var.prefix}-allowed-locations"
  display_name         = "Allowed locations: ${var.location}"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = { value = [var.location] }
  })
}
