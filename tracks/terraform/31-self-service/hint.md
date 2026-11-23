# tf-31 hints

Docs:
- `azurerm_federated_identity_credential`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential
- OIDC subject claims, immutable format: https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- `azurerm_consumption_budget_resource_group`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group
- Delegating role assignments with conditions: https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-portal

Traps:
- **The repo must exist before the plan.** The module reads `https://api.github.com/repos/<owner>/<repo>`
  with the `http` data source (as `terraform/bootstrap` does) to get the owner's and the repo's
  numeric IDs. A missing repo fails the plan through the data source's `postcondition`.
- **Why the IDs?** Repos created after 2026-07-15 get immutable OIDC subjects:
  `repo:learner@123/acme-payments-app@456:ref:refs/heads/main`. A subject with names only never
  matches, and `azure/login` fails with `AADSTS70021: No matching federated identity record`.
- **The rate limit.** Unauthenticated GitHub API calls get 60 an hour per IP, and runners share
  IPs. CI passes its own `github.token` as `TF_VAR_github_token`; locally the variable stays
  `null` and the module sends no `Authorization` header.
- **Why CI may now assign Contributor.** tf-04 limited CI's RBAC Administrator role to a few
  data-plane and read roles, and that condition stays as it is. `team-onboarding.tf` adds a second
  assignment that allows `Contributor`, for service principals only. Without it the apply fails
  with `AuthorizationFailed` on the role assignment. bootstrap is yours: apply it locally before
  you merge.
- **"Contributor on its own group" is the scope argument**, `azurerm_resource_group.this.id`. RBAC
  conditions can't check the scope, so review is what stops a team getting more.
- **One module call.** The stack holds the module call, its inputs and outputs, nothing else. A
  second team is the same directory with another name: that's the point of the module.
- **Tests with a fake GitHub.** The starter's tests use `mock_provider "http"` with a canned API
  answer (`mock_data`), and `override_data` to simulate a missing repo.
- **The budget's start date** must be the first of a month and is fixed at creation; reuse the
  pattern from tf-12 (`plantimestamp()` and `ignore_changes = [time_period]`).
- **Team names** become resource names: keep them short, lowercase letters and digits.
