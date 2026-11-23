# Self-service for one product team (tf-31): everything a team needs to start deploying on its own,
# from one module call, inside the resource group the platform vended for it (bootstrap creates the
# group and lets CI grant Contributor there and nowhere else).
#
# Starter: fill in every TODO(tf-31) block, then `terraform test` must pass. variables.tf,
# outputs.tf and the tests are complete; read the tests to see what is expected.

locals {
  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
    team       = var.team
  }

  repo    = jsondecode(data.http.repo.response_body)
  gh_auth = var.github_token == null ? {} : { Authorization = "Bearer ${var.github_token}" }

  # TODO(tf-31): the OIDC subject for pushes to the team repo's main branch, in the immutable
  # format repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main (local.repo holds the API answer:
  # .owner.login, .owner.id, .name, .id). terraform/bootstrap builds the same for your own repo.
  gh_subject = "TODO(tf-31)"

  # The first of this month; a budget's start date is fixed at creation (tf-12).
  budget_from = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
}

data "http" "repo" {
  url             = "https://api.github.com/repos/${var.github_repository}"
  request_headers = merge({ Accept = "application/vnd.github+json" }, local.gh_auth)

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub API did not return ${var.github_repository} (status ${self.status_code}). Does the team repo exist?"
    }
  }
}

# The team's landing spot, vended by the platform (bootstrap), not created here.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# TODO(tf-31): azurerm_user_assigned_identity "ci": id-<prefix>-<team>-ci in the vended group
# (its name and location come from the data source), tags local.tags.

# TODO(tf-31): azurerm_federated_identity_credential "main": name gh-main, for the identity
# (user_assigned_identity_id), GitHub's issuer https://token.actions.githubusercontent.com,
# audience api://AzureADTokenExchange, subject local.gh_subject.

# TODO(tf-31): azurerm_role_assignment "contributor": Contributor for the identity, scope = the
# vended group's ID, principal_type ServicePrincipal.

# TODO(tf-31): azurerm_consumption_budget_resource_group "this": budget-<prefix>-<team> on the
# vended group, var.budget_amount, Monthly, start date local.budget_from (ignore_changes on
# time_period), notifications at 80 % Actual and 100 % Forecasted to var.budget_contact_emails.
