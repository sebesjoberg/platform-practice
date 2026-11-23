# Inputs of the payments team's stack, lab values as defaults (CI needs no tfvars file).

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
  description = "Value of the owner tag on the team's resource group."
  type        = string
  default     = "{{OWNER_TAG}}"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "github_owner" {
  description = "GitHub owner (user or organisation) of the team's repo <owner>/<prefix>-payments-app."
  type        = string
  default     = "{{GH_OWNER}}"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner must be a GitHub user or organisation name."
  }
}

variable "github_token" {
  description = "Token for the GitHub API lookup of the team repo. CI sets it from its own GITHUB_TOKEN (TF_VAR_github_token); locally it may stay null."
  type        = string
  default     = null
  sensitive   = true
}

variable "budget_email" {
  description = "Recipient of the team budget's alerts. CI sets it from the GitHub secret BUDGET_EMAIL (TF_VAR_budget_email)."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.budget_email))
    error_message = "budget_email must be an email address (set the GitHub secret BUDGET_EMAIL)."
  }
}
