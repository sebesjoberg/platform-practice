variable "env" {
  description = "Environment of the spoke: dev or prod. Part of every resource name and the env tag."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "vnet_cidr" {
  description = "CIDR block of the spoke VNet, one /16; the subnets are cut out of it: snet-app x.1.0/24, snet-pe x.2.0/24, snet-aca x.4.0/23. Called address_space before v2.0.0."
  type        = string

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && endswith(var.vnet_cidr, "/16")
    error_message = "vnet_cidr must be a /16 CIDR block, such as 10.1.0.0/16."
  }
}

variable "prefix" {
  description = "Company prefix in every resource name (<type>-<prefix>-<env>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "location" {
  description = "Azure region of the resource group, VNet and NSGs."
  type        = string
}

variable "owner" {
  description = "Value of the owner tag on the resource group and every taggable resource."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "hub" {
  description = "The hub VNet the spoke peers with: its resource group, name and ID."
  type = object({
    resource_group_name = string
    vnet_name           = string
    vnet_id             = string
  })

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.hub.vnet_id))
    error_message = "hub.vnet_id must be the Azure resource ID of a virtual network."
  }
}

variable "private_dns_zone_ids" {
  description = "Private DNS zones to link the spoke VNet to: zone name (privatelink.*) => the zone's resource ID. Replaces private_dns_zone_names (v3.0.0): azurerm 5.x links a VNet to a zone by its ID."
  type        = map(string)

  validation {
    condition     = alltrue([for name, id in var.private_dns_zone_ids : startswith(name, "privatelink.") && endswith(lower(id), "/providers/microsoft.network/privatednszones/${name}")])
    error_message = "private_dns_zone_ids must map privatelink.* zone names to the resource IDs of those zones."
  }
}
