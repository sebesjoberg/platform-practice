# tf-31 solution

## Approach

1. Create the team repo, so the module can look it up.
2. Copy the starters; apply bootstrap locally (CI may now assign `Contributor` to managed
   identities).
3. Modules repo: `team-env/main.tf`, tests, README, changelog, release `v3.1.0`.
4. Platform repo: `terraform/teams/payments` with one module call, its lock file, the
   Dependabot line and `TF_VAR_github_token` in both workflows. One PR.

## Code

`team-env/main.tf` in the modules repo:

```hcl
locals {
  tags = { owner = var.owner, env = var.env, managed_by = "terraform", team = var.team }

  repo        = jsondecode(data.http.repo.response_body)
  gh_subject  = "repo:${local.repo.owner.login}@${local.repo.owner.id}/${local.repo.name}@${local.repo.id}:ref:refs/heads/main"
  gh_auth     = var.github_token == null ? {} : { Authorization = "Bearer ${var.github_token}" }
  budget_from = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
}

data "http" "repo" {
  url             = "https://api.github.com/repos/${var.github_repository}"
  request_headers = merge({ Accept = "application/vnd.github+json" }, local.gh_auth)

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub API did not return ${var.github_repository} (status ${self.status_code})."
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}-${var.team}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-${var.prefix}-${var.team}-ci"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
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
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_consumption_budget_resource_group" "this" {
  name              = "budget-${var.prefix}-${var.team}"
  resource_group_id = azurerm_resource_group.this.id
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

  team              = "payments"
  prefix            = var.prefix
  location          = var.location
  owner             = var.owner
  github_repository = "${var.github_owner}/${var.prefix}-payments-app"
  github_token      = var.github_token

  budget_amount         = 100
  budget_contact_emails = [var.budget_email]
}

output "payments_azure_client_id" {
  value = module.team_payments.identity_client_id
}
```

Both workflows, in `env`:

```yaml
  TF_VAR_github_token: ${{ github.token }}
```

`.github/dependabot.yml`: add `- "/terraform/teams/payments"` to the terraform directories.

## Commands

```bash
gh repo create {{GH_OWNER}}/{{PREFIX}}-payments-app --public --description "Payments team"
cp -rn ~/.platform-lab/starter/tf-31/team-env "$MODULES_DIR/"
cp -rn ~/.platform-lab/starter/tf-31/live/terraform/. "$LIVE_DIR/terraform/"
(cd "$LIVE_DIR/terraform/bootstrap" && terraform init && terraform apply)

cd "$MODULES_DIR/team-env"   # write main.tf
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
```

Hand the team `payments_azure_client_id` (and the tenant and subscription IDs) as repo
variables. A workflow on their `main` with `permissions: id-token: write` and `azure/login` can
now deploy into `rg-{{PREFIX}}-payments`, and nowhere else.

## Cost

An empty resource group, an identity, a role assignment and a budget cost nothing. `./lab.sh pause`
destroys the stack anyway (the identity comes back with a new client ID on resume); `nuke` asks
before it deletes the team repo.
