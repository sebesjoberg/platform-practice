# tf-22 hints

Docs:
- `azurerm_container_registry`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
- Resource IDs and how they're built: https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules
- Import images into a registry: https://learn.microsoft.com/azure/container-registry/container-registry-import-images
- Registry authentication with managed identities: https://learn.microsoft.com/azure/container-registry/container-registry-authentication-managed-identity

Traps:
- **Who grants access to a shared thing?** The consumer, in its own stack. `shared` runs before
  the env stacks, so on a fresh build the app identities don't exist yet when it applies. The
  env stack assigns `AcrPull` to its own identity. `shared` never needs to know which
  environments exist.
- **Why not a data source for the registry?** The plan job plans every stack on the PR, before
  anything is applied. A `data "azurerm_container_registry"` in env-dev would look for a
  registry that only this PR creates, fail the plan, and `plan` is the required check. A
  resource ID is just names:
  `/subscriptions/<id>/resourceGroups/rg-{{PREFIX}}-shared/providers/Microsoft.ContainerRegistry/registries/acr{{PREFIX}}{{SUFFIX}}`
  (`data.azurerm_client_config.current.subscription_id` gives the subscription without an API
  lookup). The alternative is two PRs: shared first, then the env stack.
- **The pipeline finds the new stack itself.** `stacks.sh` picks up any directory under
  `terraform/` with an `azurerm` backend, and `STACK_ORDER` already places `shared` after
  landing-zone. No workflow change.
- **Registry names** are global, 5–50 letters and digits, no hyphens: hence
  `acr{{PREFIX}}{{SUFFIX}}`.
- **No admin user.** It's a shared username and password. Pulls authenticate with Entra ID:
  `AcrPull` for the identity that pulls.
- **CI can assign `AcrPull`** because it's one of the roles in its RBAC Administrator condition
  (tf-04). Any other role would fail with `AuthorizationFailed`.
- **Import, don't push.** `az acr import` copies an image registry to registry inside Azure: no
  Docker on your machine. It needs the registry to exist, so import after the apply. Run it
  again after `./lab.sh pause`? No: `./lab.sh resume` re-imports it when the pipeline brings
  the registry back.
