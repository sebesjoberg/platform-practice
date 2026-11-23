variable "name" {
  description = "VM name (vm-<prefix>-<role>...). The NIC is <name>-nic."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$", var.name))
    error_message = "name must be 2 to 64 lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "Existing resource group of the VM, its NIC, disk and public IP."
  type        = string
}

variable "location" {
  description = "Azure region of the VM."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet the VM's NIC joins (it may live in another resource group)."
  type        = string

  validation {
    condition     = can(regex("/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be the Azure resource ID of a subnet."
  }
}

variable "size" {
  description = "VM size. The lab's default is the cheapest current x64 B-series size in swedencentral (see the platform repo's README)."
  type        = string
  default     = "Standard_B2ats_v2"

  validation {
    condition     = startswith(var.size, "Standard_B")
    error_message = "size must be a B-series size (Standard_B...): the lab runs on burstable VMs only."
  }
}

variable "admin_username" {
  description = "Login user. SSH key only: password authentication is always off."
  type        = string
  default     = "azureuser"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["root", "admin", "administrator"], var.admin_username)
    error_message = "admin_username must be a lowercase Linux user name, not root, admin or administrator."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key of admin_username (ssh-ed25519 or ssh-rsa of at least 2048 bits). The private key never goes near Terraform. Used when the VM is created; a later change doesn't replace the VM."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/=]+( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be an OpenSSH public key line starting with ssh-ed25519 or ssh-rsa."
  }
}

variable "extra_ssh_public_keys" {
  description = "More OpenSSH public keys for admin_username, next to ssh_public_key (e.g. a CI runner's, so it can reach a brand-new VM). Like ssh_public_key they only count when the VM is created: changing the keys never replaces a running VM."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for k in var.extra_ssh_public_keys : can(regex("^(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/=]+( .*)?$", trimspace(k)))])
    error_message = "extra_ssh_public_keys must be OpenSSH public key lines starting with ssh-ed25519 or ssh-rsa."
  }
}

variable "public_ip_name" {
  description = "Name of a Standard, static public IP to attach (pip-<prefix>-<role>). null (the default): no public IP."
  type        = string
  default     = null
}

variable "system_assigned_identity" {
  description = "Give the VM a system-assigned managed identity (its principal_id is an output)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags of the VM, NIC and public IP. Inventory keys on them (role, env)."
  type        = map(string)
  default     = {}
}
