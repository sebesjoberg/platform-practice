# Self-service for one product team (tf-31): everything a team needs to start deploying on its own,
# from one module call, inside the resource group the platform vended for it (bootstrap creates
# the group and lets CI grant Contributor there and nowhere else). A budget on the group, and an
# identity that the team's repo (main branch only) can use from GitHub Actions with OIDC,
# Contributor on that group and nothing else. No secrets: the team stores three IDs as repo
# variables, as the platform did in tf-05.

locals {
  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
    team       = var.team
  }

  # GitHub repos created after 2026-07-15 use immutable OIDC subjects,
  # repo:OWNER@OWNER_ID/REPO@REPO_ID:<context>, as the platform's own credentials do (tf-04).
  repo        = jsondecode(data.http.repo.response_body)
  gh_subject  = "repo:${local.repo.owner.login}@${local.repo.owner.id}/${local.repo.name}@${local.repo.id}:ref:refs/heads/main"
  gh_headers  = { Accept = "application/vnd.github+json" }
  gh_auth     = var.github_token == null ? {} : { Authorization = "Bearer ${var.github_token}" }
  budget_from = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
}

data "http" "repo" {
  url             = "https://api.github.com/repos/${var.github_repository}"
  request_headers = merge(local.gh_headers, local.gh_auth)

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub API did not return ${var.github_repository} (status ${self.status_code}). Does the team repo exist?"
    }
  }
}

# The team's landing spot, vended by the platform (bootstrap), not created here: this module, run
# by CI, may only operate inside it.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# The identity the team's pipeline runs as. It lives in the team's own group, so deleting the team
# deletes it.
resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-${var.prefix}-${var.team}-ci"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  tags                = local.tags
}

# Only pushes to the team repo's main branch get a token for this identity: no PRs, no forks, no
# other branches.
resource "azurerm_federated_identity_credential" "main" {
  name                      = "gh-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.gh_subject
}

# Contributor on the team's group only: the team builds what it wants inside it and nothing
# outside. Contributor can't assign roles, so the team can't widen its own access. CI may create
# this assignment only because bootstrap allowed it on this group (team-vending.tf).
resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_consumption_budget_resource_group" "this" {
  name              = "budget-${var.prefix}-${var.team}"
  resource_group_id = data.azurerm_resource_group.this.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = local.budget_from # the first of this month; fixed at creation (ignore_changes)
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    # plantimestamp() moves every month; changing start_date would replace the budget.
    ignore_changes = [time_period]
  }
}
