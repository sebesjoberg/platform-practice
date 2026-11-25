---
id: tf-08
title: Hub network
target_minutes: 20
requires: [tf-07]
---
# tf-08 Hub network

Acme goes hub and spoke. The hub holds what every environment shares: later a jump/runner
host and private endpoints. The network team hands you the address plan and one rule:
every subnet gets its own network security group, and nothing is opened that no task needs.

## Deliverables

In `terraform/landing-zone`, using the conventions from tf-07 (names from `var.prefix`,
`local.tags["hub"]`):

- [ ] Virtual network `vnet-{{PREFIX}}-hub` in `rg-{{PREFIX}}-hub`, address space
      `10.0.0.0/16`.
- [ ] Three subnets as separate `azurerm_subnet` resources:

  | Subnet | Prefix | NSG |
  |---|---|---|
  | `snet-shared` | `10.0.1.0/24` | `nsg-{{PREFIX}}-hub-shared` |
  | `snet-runner` | `10.0.2.0/24` | `nsg-{{PREFIX}}-hub-runner` |
  | `snet-pe` | `10.0.3.0/24` | `nsg-{{PREFIX}}-hub-pe` |

- [ ] One network security group per subnet (names above, in `rg-{{PREFIX}}-hub`, hub
      tags), associated with its subnet. **No custom security rules.** The defaults already
      allow VNet-internal traffic and deny inbound internet traffic. tf-25 adds the one rule
      the jump host needs.
- [ ] Shipped through a PR (read the plan: 1 VNet, 3 subnets, 3 NSGs, 3 associations to add,
      nothing to change or destroy) and applied by the pipeline.

## Done when

`az network vnet subnet list -g rg-{{PREFIX}}-hub --vnet-name vnet-{{PREFIX}}-hub -o table`
shows the three subnets, each with its NSG, and `./lab.sh grade` passes.
