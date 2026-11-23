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
