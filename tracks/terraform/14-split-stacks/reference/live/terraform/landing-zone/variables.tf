# Inputs of the landing zone. Defaults hold the lab values, so CI needs no tfvars file; the
# validations stop a typo before it reaches Azure.

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

variable "budget_email" {
  description = "Recipient of the budget alerts. CI sets it from the GitHub variable BUDGET_EMAIL (TF_VAR_budget_email)."
  type        = string
  sensitive   = true # keeps the address out of plan output, which is public in PR comments

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.budget_email))
    error_message = "budget_email must be an email address (set the GitHub variable BUDGET_EMAIL)."
  }
}
