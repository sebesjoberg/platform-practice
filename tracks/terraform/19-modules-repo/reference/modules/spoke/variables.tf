variable "env" {
  description = "Environment of the spoke: dev or prod. Part of every resource name and the env tag."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "address_space" {
  description = "Address space of the spoke VNet, one /16 CIDR block. The subnets are cut out of it: snet-app x.1.0/24, snet-pe x.2.0/24, snet-aca x.4.0/23."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a /16 CIDR block, such as 10.1.0.0/16."
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
  description = "The hub VNet the spoke peers with: its resource group (which also holds the private DNS zones), name and ID."
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

variable "private_dns_zone_names" {
  description = "Private DNS zones in the hub resource group to link the spoke VNet to (privatelink.* zones)."
  type        = set(string)

  validation {
    condition     = alltrue([for z in var.private_dns_zone_names : startswith(z, "privatelink.")])
    error_message = "private_dns_zone_names must only contain privatelink.* zones."
  }
}
