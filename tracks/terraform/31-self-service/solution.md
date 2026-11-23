# tf-31 solution

## Approach

1. Create the team repo, so the module can look it up.
2. **Vend** (you, locally): bootstrap's `team-vending.tf` creates `rg-{{PREFIX}}-payments` and an RBAC
   Administrator assignment for CI on that group, limited to `Contributor` for service principals.
3. **Module** (modules repo): `team-env/main.tf` operates inside the vended group: identity,
   federated credential, `Contributor`, budget. Tests, README, changelog, release `v3.1.0`.
4. **Onboard** (platform repo, one PR): `terraform/teams/payments` with one module call, its lock
   file, the Dependabot line and `TF_VAR_github_token` on the Terraform steps.

The platform vends a scoped landing spot; the team operates inside it. CI never holds the right to
grant `Contributor` at subscription scope.

## Code

`terraform/bootstrap/team-vending.tf` (the starter):

```hcl
locals {
  teams               = { payments = { env = "dev" } }
  contributor_role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c"
}

resource "azurerm_resource_group" "team" {
  for_each = local.teams

  name     = "rg-{{PREFIX}}-${each.key}"
  location = "{{LOCATION}}"
  tags     = { owner = "{{OWNER_TAG}}", env = each.value.env, managed_by = "terraform", team = each.key }
}

resource "azurerm_role_assignment" "ci_team_rbac" {
  for_each = local.teams

  scope                = azurerm_resource_group.team[each.key].id   # this group, nothing else
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    ... write/delete only if RoleDefinitionId is Contributor AND PrincipalType is ServicePrincipal
  EOT
}
```

`team-env/main.tf` in the modules repo, the parts the TODOs ask for:

```hcl
locals {
  gh_subject = "repo:${local.repo.owner.login}@${local.repo.owner.id}/${local.repo.name}@${local.repo.id}:ref:refs/heads/main"
}

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-${var.prefix}-${var.team}-ci"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "main" {
  name                      = "gh-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.gh_subject
}

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
    start_date = local.budget_from
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
    ignore_changes = [time_period]
  }
}
```

`terraform/teams/payments/main.tf` in the platform repo (versions and variables from the
starter):

```hcl
module "team_payments" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//team-env?ref=v3.1.0"

  team                = "payments"
  prefix              = var.prefix
  resource_group_name = "rg-${var.prefix}-payments" # vended by bootstrap
  owner               = var.owner
  github_repository   = "${var.github_owner}/${var.prefix}-payments-app"
  github_token        = var.github_token

  budget_amount         = 100
  budget_contact_emails = [var.budget_email]
}

output "payments_azure_client_id" {
  value = module.team_payments.identity_client_id
}
```

`terraform.yml` (the plan step and the apply step) and `drift.yml` (the plan step), in the step's
`env`:

```yaml
          TF_VAR_github_token: ${{ github.token }}
```

`.github/dependabot.yml`: add `- "/terraform/teams/payments"` to the terraform directories.

## Commands

```bash
gh repo create {{GH_OWNER}}/{{PREFIX}}-payments-app --public --description "Payments team"
cp -rn ~/.platform-lab/starter/tf-31/team-env "$MODULES_DIR/"
cp -rn ~/.platform-lab/starter/tf-31/live/terraform/. "$LIVE_DIR/terraform/"
(cd "$LIVE_DIR/terraform/bootstrap" && terraform init && terraform apply)   # vend: 2 to add

cd "$MODULES_DIR/team-env"   # fill in the TODO(tf-31) blocks of main.tf
terraform init -backend=false && terraform test
terraform-docs markdown table --output-file README.md --output-mode inject .
cd .. && git switch -c team-env && git add -A && git commit -m "team-env module (v3.1.0)"
git push -u origin team-env && gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull && git tag -a v3.1.0 -m "v3.1.0: team-env" && git push origin v3.1.0

cd "$LIVE_DIR/terraform/teams/payments"   # write main.tf
terraform init -backend=false && terraform providers lock -platform=linux_amd64 -platform=windows_amd64
cd "$LIVE_DIR" && git switch -c onboard-payments && git add -A && git commit -m "tf-31: onboard the payments team"
git push -u origin onboard-payments && gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
```

## Verify

```bash
az identity federated-credential list -g rg-{{PREFIX}}-payments --identity-name id-{{PREFIX}}-payments-ci --query "[].subject" -o tsv
az role assignment list --assignee "$(az identity show -g rg-{{PREFIX}}-payments -n id-{{PREFIX}}-payments-ci --query principalId -o tsv)" --all -o table
ci="$(az identity show -g rg-{{PREFIX}}-tfstate -n id-{{PREFIX}}-github-ci --query principalId -o tsv)"
az role assignment list --assignee "$ci" --all --query "[?roleDefinitionName=='Role Based Access Control Administrator'].scope" -o tsv
# the subscription (the tf-04 condition, data-plane roles only) and rg-{{PREFIX}}-payments (Contributor)
```

Hand the team `payments_azure_client_id` (and the tenant and subscription IDs) as repo
variables. A workflow on their `main` with `permissions: id-token: write` and `azure/login` can
now deploy into `rg-{{PREFIX}}-payments`, and nowhere else.

## Cost

An empty resource group, an identity, a role assignment and a budget cost nothing.
`./lab.sh pause` destroys the team stack (the identity comes back with a new client ID on resume)
and keeps the vended group; `nuke` deletes the group and asks before it deletes the team repo.
