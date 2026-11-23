---
id: tf-09
title: Spokes with for_each
target_minutes: 20
requires: [tf-08]
---
# tf-09 Spokes with for_each

Development and production get their own networks, peered with the hub. The CTO doesn't want
two copy-pasted blocks that drift apart: one definition, stamped out per environment from
`var.envs`. Adding an environment later should be a one-line change.

## Deliverables

In `terraform/landing-zone`, every resource below defined **once** with `for_each` (over
`var.envs`, or over a map derived from it), never copied per environment:

- [ ] Resource groups `rg-{{PREFIX}}-dev` and `rg-{{PREFIX}}-prod` in `{{LOCATION}}`, tags
      from tf-07 with `env = "dev"` / `env = "prod"`.
- [ ] Virtual networks `vnet-{{PREFIX}}-dev` (`10.1.0.0/16`) and `vnet-{{PREFIX}}-prod`
      (`10.2.0.0/16`) in their groups.
- [ ] The same three subnets in each spoke (`x` = 1 for dev, 2 for prod):

  | Subnet | Prefix | Notes |
  |---|---|---|
  | `snet-app` | `10.x.1.0/24` | VMs (tf-25) |
  | `snet-pe` | `10.x.2.0/24` | private endpoints (tf-21) |
  | `snet-aca` | `10.x.4.0/23` | delegated to `Microsoft.App/environments` (Container Apps, tf-23) |

- [ ] An NSG per spoke subnet, named nsg-{{PREFIX}}-<env>-<subnet> (e.g.
      `nsg-{{PREFIX}}-dev-app`, `nsg-{{PREFIX}}-prod-aca`), in the spoke's group, associated
      with its subnet, no custom rules.
- [ ] Peering in **both** directions per spoke: `peer-hub-to-dev` / `peer-dev-to-hub` and
      `peer-hub-to-prod` / `peer-prod-to-hub`. Each peering lives on the VNet it starts from.
- [ ] Shipped through a PR and applied by the pipeline.

## Done when

`az network vnet peering list -g rg-{{PREFIX}}-hub --vnet-name vnet-{{PREFIX}}-hub -o table`
shows both hub peerings `Connected`, the spoke subnets show their NSGs and the `snet-aca`
delegation, and `./lab.sh grade` passes.

Target: 20 minutes.
