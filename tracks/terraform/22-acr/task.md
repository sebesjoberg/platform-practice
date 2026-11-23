---
id: tf-22
title: A shared container registry
target_minutes: 15
requires: [tf-21]
---
# tf-22 A shared container registry

The product team's service ships as a container image. Images are built once and promoted from
dev to prod by tag, so the registry belongs to neither environment: it's a shared platform
service. Its stack, `shared`, already has a place in the pipeline's `STACK_ORDER`.

## Deliverables

- [ ] A new stack `terraform/shared`, same conventions as the others: backend key
      `shared.tfstate`, validated variables with the lab values as defaults (including
      `suffix`).
  - resource group `rg-{{PREFIX}}-shared` with the tags `owner = "{{OWNER_TAG}}"`,
    `env = "hub"`, `managed_by = "terraform"`
  - container registry `acr{{PREFIX}}{{SUFFIX}}` in it: SKU `Basic`, admin user disabled
  - output `acr_login_server`
- [ ] In `terraform/env-dev`: find the registry with a data source and give
      `id-{{PREFIX}}-app-dev` the role `AcrPull` on it.
- [ ] One PR, merged, applied by the pipeline (shared runs before env-dev).
- [ ] Then put the app image into the registry. Terraform doesn't push images; you import
      Microsoft's Container Apps quickstart image once:

  ```bash
  az acr import --name acr{{PREFIX}}{{SUFFIX}} \
    --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0
  ```

## Done when

`az acr repository show-tags -n acr{{PREFIX}}{{SUFFIX}} --repository hello -o tsv` prints `1.0`,
`az role assignment list --scope $(az acr show -n acr{{PREFIX}}{{SUFFIX}} --query id -o tsv) -o table`
shows `AcrPull` for the app identity, and `./lab.sh grade` passes.

Target: 15 minutes.
