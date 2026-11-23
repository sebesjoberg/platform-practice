# Plan-only tests for team-env. mock_provider fakes azurerm; the http data source gets a canned
# GitHub API answer, so nothing reaches GitHub or Azure.

mock_provider "azurerm" {}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = "{\"id\": 4242, \"name\": \"acme-payments-app\", \"owner\": {\"login\": \"learner\", \"id\": 77}}"
    }
  }
}

variables {
  team                  = "payments"
  prefix                = "acme"
  location              = "swedencentral"
  owner                 = "platform-team"
  github_repository     = "learner/acme-payments-app"
  budget_amount         = 100
  budget_contact_emails = ["payments@example.com"]
}

run "names_tags_and_budget" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-acme-payments" && azurerm_user_assigned_identity.ci.name == "id-acme-payments-ci" && azurerm_consumption_budget_resource_group.this.name == "budget-acme-payments"
    error_message = "names must be rg-<prefix>-<team>, id-<prefix>-<team>-ci and budget-<prefix>-<team>"
  }

  assert {
    condition     = azurerm_resource_group.this.tags["owner"] == "platform-team" && azurerm_resource_group.this.tags["env"] == "dev" && azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.tags["team"] == "payments"
    error_message = "the resource group needs owner, env, managed_by and team tags"
  }

  assert {
    condition     = azurerm_consumption_budget_resource_group.this.amount == 100 && azurerm_consumption_budget_resource_group.this.time_grain == "Monthly" && length(azurerm_consumption_budget_resource_group.this.notification) == 2
    error_message = "the budget is the given amount, monthly, with two notifications"
  }
}

run "main_branch_only" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.main.subject == "repo:learner@77/acme-payments-app@4242:ref:refs/heads/main"
    error_message = "the federated credential must trust only the team repo's main branch, in the immutable subject format"
  }

  assert {
    condition     = azurerm_federated_identity_credential.main.issuer == "https://token.actions.githubusercontent.com" && azurerm_federated_identity_credential.main.audience[0] == "api://AzureADTokenExchange"
    error_message = "GitHub's issuer and the Azure token exchange audience"
  }

  assert {
    condition     = azurerm_role_assignment.contributor.role_definition_name == "Contributor"
    error_message = "the team's identity gets Contributor (on its own group)"
  }
}

run "rejects_a_team_name_with_a_hyphen" {
  command = plan

  variables {
    team = "pay-ments"
  }

  expect_failures = [var.team]
}

run "fails_when_the_repo_does_not_exist" {
  command = plan

  override_data {
    target = data.http.repo
    values = {
      status_code   = 404
      response_body = "{\"id\": 0, \"name\": \"x\", \"owner\": {\"login\": \"x\", \"id\": 0}}"
    }
  }

  expect_failures = [data.http.repo]
}
