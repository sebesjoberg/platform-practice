# The payments team (tf-31): onboarded with one module call. Everything the team gets is in the
# team-env module of the modules repo; a new team is a copy of this directory with another name,
# a backend key teams-<team>.tfstate and a line in STACK_ORDER and dependabot.yml.

module "team_payments" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//team-env?ref=v3.1.0"

  team              = "payments"
  prefix            = var.prefix
  location          = var.location
  owner             = var.owner
  github_repository = "${var.github_owner}/${var.prefix}-payments-app"
  github_token      = var.github_token

  budget_amount         = 100
  budget_contact_emails = [var.budget_email]
}

# What the team needs to log in from its own workflows (azure/login with OIDC). None of it is a
# secret; hand it over as repo variables in the team's repo.
output "payments_azure_client_id" {
  description = "AZURE_CLIENT_ID for the payments team's repo."
  value       = module.team_payments.identity_client_id
}

output "payments_resource_group" {
  description = "The payments team's resource group."
  value       = module.team_payments.resource_group_name
}

output "payments_federated_subject" {
  description = "The OIDC subject the team's identity trusts (their repo's main branch)."
  value       = module.team_payments.federated_subject
}
