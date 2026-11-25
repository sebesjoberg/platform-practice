---
id: tf-23
title: A container app in dev
target_minutes: 20
requires: [tf-22]
---
# tf-23 A container app in dev

Everything the product team asked for exists: an identity, a vault with their greeting in it,
a registry with their image. Now run it. No passwords anywhere: the app pulls its image and
reads its secret as `id-{{PREFIX}}-app-dev`.

## Deliverables

In `terraform/env-dev`:

- [ ] Container Apps environment `cae-{{PREFIX}}-dev` in `rg-{{PREFIX}}-dev`:
  - workload profiles environment with only the `Consumption` profile (scales to zero, no
    fixed cost)
  - integrated into the spoke's `snet-aca` (already delegated to
    `Microsoft.App/environments`), with a public (not internal) load balancer
  - infrastructure resource group `ME_cae-{{PREFIX}}-dev`
  - tags `owner`, `env`, `managed_by`
- [ ] Container app `ca-{{PREFIX}}-hello-dev` in that environment:
  - user-assigned identity `id-{{PREFIX}}-app-dev`
  - image `acr{{PREFIX}}{{SUFFIX}}.azurecr.io/hello:1.0`, pulled with that identity
  - a secret `greeting` that **references** the Key Vault secret from tf-21 (versionless ID),
    read with that identity, exposed to the container as the environment variable `GREETING`
  - external ingress on target port `80`, 0.25 CPU / 0.5 Gi, between 0 and 1 replicas
- [ ] Output `hello_url`.
- [ ] One PR, merged, applied by the pipeline.

Azure creates the infrastructure resource group itself and manages what's in it (a load
balancer and a public IP for the ingress). The owner-tag policy from tf-11 only matches
resource groups whose names start with rg-, so it doesn't block it.

## Done when

`curl -fsS "$(terraform -chdir=terraform/env-dev output -raw hello_url)"` (after
`terraform init` there), or the FQDN from `az containerapp show`, answers with the quickstart
page, and `./lab.sh grade` passes.
