variable "env" {
  description = "Environment this stack builds."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "address_space" {
  description = "Address space of the spoke VNet, a /16 (subnets are cut out of it)."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a /16 CIDR block."
  }
}

variable "prefix" {
  description = "Company prefix in every resource name (<type>-<prefix>-<name>)."
  type        = string
  default     = "{{PREFIX}}"

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "{{LOCATION}}"

  validation {
    condition     = var.location == "swedencentral"
    error_message = "The platform runs in swedencentral only."
  }
}

variable "owner" {
  description = "Value of the owner tag on every resource group."
  type        = string
  default     = "{{OWNER_TAG}}"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "suffix" {
  description = "Random suffix of globally unique names (the Key Vault, from tf-21)."
  type        = string
  default     = "{{SUFFIX}}"

  validation {
    condition     = can(regex("^[a-z0-9]{6}$", var.suffix))
    error_message = "suffix must be 6 lowercase letters or digits."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key for the web VMs' admin user. CI sets it from the GitHub variable SSH_PUBLIC_KEY (TF_VAR_ssh_public_key)."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 ... or ssh-rsa ...); set the GitHub variable SSH_PUBLIC_KEY."
  }
}
