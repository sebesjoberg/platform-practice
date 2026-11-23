variable "team" {
  description = "Team name, part of every resource name (rg-<prefix>-<team>, id-<prefix>-<team>-ci, budget-<prefix>-<team>) and the team tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.team))
    error_message = "team must be 2 to 16 lowercase letters or digits, starting with a letter."
  }
}

variable "prefix" {
  description = "Company prefix in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "env" {
  description = "Value of the env tag: the environment the team deploys into (dev or prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "location" {
  description = "Azure region of the resource group and the identity."
  type        = string
}

variable "owner" {
  description = "Value of the owner tag: who answers for the team's resources."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "github_repository" {
  description = "The team's GitHub repository, owner/name. Its main branch may deploy as the team's identity (federated credential gh-main)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "github_token" {
  description = "Optional GitHub token for the repository lookup (CI passes its GITHUB_TOKEN: unauthenticated API calls are rate limited per IP). null: no token."
  type        = string
  default     = null
  sensitive   = true
}

variable "budget_amount" {
  description = "Monthly budget of the team's resource group, in the billing currency."
  type        = number

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be positive."
  }
}

variable "budget_contact_emails" {
  description = "Who gets the budget alerts (80 % actual, 100 % forecast)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.budget_contact_emails) > 0
    error_message = "budget_contact_emails needs at least one address."
  }
}
