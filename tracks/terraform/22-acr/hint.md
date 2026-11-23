# tf-22 hints

Docs:
- `azurerm_container_registry`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
- `azurerm_container_registry` data source: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/container_registry
- Import images into a registry: https://learn.microsoft.com/azure/container-registry/container-registry-import-images
- Registry authentication with managed identities: https://learn.microsoft.com/azure/container-registry/container-registry-authentication-managed-identity

Traps:
- **Who grants access to a shared thing?** The consumer, in its own stack. `shared` runs before
  the env stacks, so on a fresh build the app identities don't exist yet when it applies. The
  env stack looks the registry up by name (a data source) and assigns `AcrPull` to its own
  identity. `shared` never needs to know which environments exist.
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
