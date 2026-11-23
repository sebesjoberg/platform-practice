# tf-04 hints

Docs:
- Workload identity federation with a user-assigned managed identity:
  https://learn.microsoft.com/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity
- `azurerm_federated_identity_credential` and `azurerm_role_assignment` (see the ABAC example):
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential and
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
- Constrained role assignment delegation (the condition syntax):
  https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-examples
- GitHub OIDC subject claims, including the immutable format:
  https://docs.github.com/actions/reference/security/oidc

Traps:
- **The subject must match exactly, character for character.** Repos created after
  2026-07-15 put IDs in the subject: `repo:{{GH_OWNER}}@<owner id>/{{LIVE_REPO}}@<repo id>:...`.
  Older docs and blog posts show `repo:owner/repo:...`, which no longer matches a new repo.
  The login fails later in CI with `AADSTS700213: No matching federated identity record found`.
  The `sub_claim_prefix` from the GitHub API is the source of truth. Hard-coding it in a local is
  fine. The reference looks the IDs up with the `http` data source from the public repo API.
- **Environment jobs get a different subject.** A job with `environment: prod` presents
  `...:environment:prod`, not `...:ref:refs/heads/main`. That's why `gh-env-prod` exists.
  It's used once the prod environment deploys (later in the lab).
- **Role definition GUIDs, not names, in the condition.** Look them up with
  `az role definition list --name "AcrPull" --query "[].name" -o tsv`. The condition needs a
  write part (`@Request[...]`) *and* a delete part (`@Resource[...]`). Otherwise CI could
  remove any assignment, Owner included.
- `principal_type = "ServicePrincipal"` on the role assignments skips a directory lookup that
  can fail for a brand-new identity ("principal does not exist in the directory").
- The container's ID in azurerm 4.x (with `storage_account_id`) is its Resource Manager ID,
  which is exactly the scope you need for a container-level role assignment.
- Federated credentials on one identity can't be written in parallel (Azure returns
  `ConcurrentFederatedIdentityCredentialsWritesForSingleManagedIdentity`). The azurerm
  provider serialises them for you. Other tools may not.
- None of the IDs (client ID, tenant ID, subscription ID) is a secret. In tf-05 they become
  repo *variables*.
