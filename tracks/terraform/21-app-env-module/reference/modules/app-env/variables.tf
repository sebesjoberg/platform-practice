variable "env" {
  description = "Environment: dev or prod. Part of every resource name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
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

variable "suffix" {
  description = "Random suffix that makes the Key Vault name globally unique (kv-<prefix>-<env>-<suffix>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{6}$", var.suffix))
    error_message = "suffix must be 6 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region of every resource."
  type        = string
}

variable "owner" {
  description = "Value of the owner tag on every resource."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the workload resources (the spoke's rg-<prefix>-<env>)."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "ID of the subnet that gets the vault's private endpoint (the spoke's snet-pe)."
  type        = string

  validation {
    condition     = can(regex("/subnets/[^/]+$", var.private_endpoint_subnet_id))
    error_message = "private_endpoint_subnet_id must be the Azure resource ID of a subnet."
  }
}

variable "key_vault_dns_zone_id" {
  description = "ID of the private DNS zone privatelink.vaultcore.azure.net (in the hub) for the endpoint's DNS zone group."
  type        = string

  validation {
    condition     = endswith(lower(var.key_vault_dns_zone_id), "/privatednszones/privatelink.vaultcore.azure.net")
    error_message = "key_vault_dns_zone_id must be the ID of the privatelink.vaultcore.azure.net zone."
  }
}

variable "secrets" {
  description = "Secrets to write into the vault, name => value. The identity running Terraform writes them (Key Vault Secrets Officer on this vault)."
  type        = map(string)
  default     = {}
  sensitive   = true
}
