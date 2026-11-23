# team-env

Self-service onboarding for one product team: everything a team needs to deploy on its own,
inside the resource group the platform vended for it.

- the platform (its bootstrap, applied by the subscription owner) creates `rg-<prefix>-<team>` and
  lets the pipeline's identity assign `Contributor` to managed identities in that group only;
  this module reads the group and works inside it
- CI identity `id-<prefix>-<team>-ci` with one federated credential, `gh-main`, for pushes to
  the team repo's `main` branch (immutable OIDC subject `repo:OWNER@ID/REPO@ID:ref:refs/heads/main`,
  with the IDs read from GitHub's API)
- `Contributor` for that identity on the team's group, nowhere else
- a monthly budget `budget-<prefix>-<team>` with alerts at 80 % actual and 100 % forecast

The team repo and the vended group must exist before the plan: the module looks both up. The
identity that runs Terraform must be allowed to assign `Contributor` in the group (the vending
grants CI exactly that, for managed identities only).

## Usage

```hcl
module "team_payments" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//team-env?ref=v3.1.0"

  team                = "payments"
  prefix              = "acme"
  resource_group_name = "rg-acme-payments" # vended by the platform
  owner               = "platform-team"
  github_repository   = "{{GH_OWNER}}/acme-payments-app"
  github_token        = var.github_token # optional; CI passes its GITHUB_TOKEN

  budget_amount         = 100
  budget_contact_emails = [var.budget_email]
}
```

The team then sets three repo variables (`AZURE_CLIENT_ID` = `identity_client_id`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and logs in with `azure/login` from a workflow on
`main` with `id-token: write`.

The section below is generated: run
`terraform-docs markdown table --output-file README.md --output-mode inject .` in this
directory after changing an input or output.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.14, < 6.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.4, < 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.14, < 6.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.4, < 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_consumption_budget_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) | resource |
| [azurerm_federated_identity_credential.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.ci](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [http_http.repo](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monthly budget of the team's resource group, in the billing currency. | `number` | n/a | yes |
| <a name="input_budget_contact_emails"></a> [budget\_contact\_emails](#input\_budget\_contact\_emails) | Who gets the budget alerts (80 % actual, 100 % forecast). | `list(string)` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Value of the env tag on the identity: the environment the team deploys into (dev or prod). | `string` | `"dev"` | no |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | The team's GitHub repository, owner/name. Its main branch may deploy as the team's identity (federated credential gh-main). | `string` | n/a | yes |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | Optional GitHub token for the repository lookup (CI passes its GITHUB\_TOKEN: unauthenticated API calls are rate limited per IP). null: no token. | `string` | `null` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Value of the owner tag on the identity: who answers for the team's resources. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Company prefix in every resource name. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The team's resource group (rg-<prefix>-<team>), vended by the platform before this module runs. Everything the module creates lives in it or applies to it. | `string` | n/a | yes |
| <a name="input_team"></a> [team](#input\_team) | Team name, part of the resource names (id-<prefix>-<team>-ci, budget-<prefix>-<team>) and the team tag. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_budget_id"></a> [budget\_id](#output\_budget\_id) | Resource ID of the team's budget. |
| <a name="output_federated_subject"></a> [federated\_subject](#output\_federated\_subject) | The OIDC subject the identity trusts: the team repo's main branch. |
| <a name="output_identity_client_id"></a> [identity\_client\_id](#output\_identity\_client\_id) | Client ID of the team's CI identity: the team's AZURE\_CLIENT\_ID repo variable. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal ID of the team's CI identity, for further role assignments. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The team's resource group (rg-<prefix>-<team>), as vended by the platform. |
<!-- END_TF_DOCS -->
