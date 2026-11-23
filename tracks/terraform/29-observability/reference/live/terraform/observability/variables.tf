# Inputs of the observability stack, lab values as defaults (CI needs no tfvars file).

variable "prefix" {
  description = "Company prefix in every resource name (<type>-<prefix>-<name>)."
  type        = string
  default     = "{{PREFIX}}"

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "owner" {
  description = "Value of the owner tag."
  type        = string
  default     = "{{OWNER_TAG}}"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}
