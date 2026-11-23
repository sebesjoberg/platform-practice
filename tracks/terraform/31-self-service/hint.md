# tf-31 hints

Docs:
- `azurerm_federated_identity_credential`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential
- OIDC subject claims, immutable format: https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- `azurerm_consumption_budget_resource_group`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group
- Delegating role assignments with conditions: https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-portal

Traps:
- **Vend first, then onboard.** The team's stack reads `rg-{{PREFIX}}-payments` with a data source and
  assigns `Contributor` in it. Both fail until bootstrap has created the group and CI's scoped
  RBAC Administrator assignment: apply bootstrap locally before you merge the stack.
- **Why the group lives in bootstrap.** The scope is the guardrail. tf-04 kept CI's subscription-wide
  RBAC Administrator role to a few data-plane and read roles, and that stays. The vended
  assignment adds `Contributor`, but only on the team's group and only for service principals
  (RBAC conditions can check the role and the principal type, not the scope; the assignment's
  own scope does that). If CI created the group itself, it would need the right on the whole
  subscription. Without the vending, the apply fails with `AuthorizationFailed` on the role
  assignment.
- **The repo must exist before the plan.** The module reads `https://api.github.com/repos/<owner>/<repo>`
  with the `http` data source (as `terraform/bootstrap` does) to get the owner's and the repo's
  numeric IDs. A missing repo fails the plan through the data source's `postcondition`.
- **Why the IDs?** Repos created after 2026-07-15 get immutable OIDC subjects:
  `repo:learner@123/acme-payments-app@456:ref:refs/heads/main`. A subject with names only never
  matches, and `azure/login` fails with `AADSTS70021: No matching federated identity record`.
- **The rate limit.** Unauthenticated GitHub API calls get 60 an hour per IP, and runners share
  IPs. CI passes its own `github.token` as `TF_VAR_github_token`, on the Terraform steps only;
  locally the variable stays `null` and the module sends no `Authorization` header.
- **One module call.** The stack holds the module call, its inputs and outputs, nothing else. A
  second team is an entry in `team-vending.tf` plus a copy of the stack directory: that's the
  point of the module.
- **Tests with fakes.** The tests mock azurerm (with a realistic group ID for the data source,
  since the budget validates it) and use `mock_provider "http"` with a canned API answer, plus
  `override_data` to simulate a missing repo.
- **The budget's start date** must be the first of a month and is fixed at creation; reuse the
  pattern from tf-12 (`plantimestamp()` and `ignore_changes = [time_period]`).
