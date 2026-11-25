---
id: tf-10
title: Private DNS zones
target_minutes: 15
requires: [tf-09]
---
# tf-10 Private DNS zones

Workloads will reach Key Vault and storage through private endpoints, never over the
internet. A private endpoint only helps if its name resolves to the private IP, from every
network. The platform owns the DNS zones centrally in the hub, and every VNet gets a link.

## Deliverables

In `terraform/landing-zone`:

- [ ] Private DNS zones `privatelink.vaultcore.azure.net` and
      `privatelink.blob.core.windows.net` in `rg-{{PREFIX}}-hub` (hub tags).
- [ ] Each zone linked to all three VNets, links named `link-<vnet name>`:
      `link-vnet-{{PREFIX}}-hub`, `link-vnet-{{PREFIX}}-dev`, `link-vnet-{{PREFIX}}-prod`
      (six links in total). Auto-registration **off**.
- [ ] Use `for_each`, not six copies. Keep the hub links and the spoke links as two separate
      resources (the spoke links follow `var.envs`; tf-14 moves them).
- [ ] Shipped through a PR and applied by the pipeline.

## Done when

`az network private-dns link vnet list -g rg-{{PREFIX}}-hub -z privatelink.vaultcore.azure.net -o table`
lists three links, `registrationEnabled` false, and `./lab.sh grade` passes.
