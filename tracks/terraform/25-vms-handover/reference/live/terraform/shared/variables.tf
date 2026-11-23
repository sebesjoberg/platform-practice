variable "prefix" {
  description = "Company prefix in every resource name (<type>-<prefix>-<name>)."
  type        = string
  default     = "{{PREFIX}}"

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "suffix" {
  description = "Random suffix of globally unique names (the container registry)."
  type        = string
  default     = "{{SUFFIX}}"

  validation {
    condition     = can(regex("^[a-z0-9]{6}$", var.suffix))
    error_message = "suffix must be 6 lowercase letters or digits."
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

variable "learner_ip" {
  description = "Your public IPv4 address: the only source allowed to SSH to the jump VM. CI sets it from the GitHub variable LEARNER_IP (TF_VAR_learner_ip)."
  type        = string
  sensitive   = true # keeps your address out of plan output, which is public in PR comments

  validation {
    condition     = can(cidrhost("${var.learner_ip}/32", 0)) && can(regex("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$", var.learner_ip))
    error_message = "learner_ip must be one IPv4 address (set the GitHub variable LEARNER_IP)."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key for the VMs' admin user. CI sets it from the GitHub variable SSH_PUBLIC_KEY (TF_VAR_ssh_public_key); the private key stays on your machine."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519 ... or ssh-rsa ...); set the GitHub variable SSH_PUBLIC_KEY."
  }
}
