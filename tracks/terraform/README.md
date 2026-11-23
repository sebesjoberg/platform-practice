# Terraform track

You build Acme's Azure platform task by task. Your code lives in your own GitHub repo
`<prefix>-platform`. From tf-05 on, every change goes through a pull request: the pipeline
plans it on the PR and applies it when you merge to `main`. Each task takes 15–20 minutes.
`./lab.sh next` starts one, `./lab.sh hint` / `solution` help, and `./lab.sh grade` checks it.

| Phase | Tasks | You build |
|---|---|---|
| 0 Foundation | tf-01 … tf-06 | tools, state storage, CI identity, PR/merge pipeline, protected `main` |
| 1 Landing zone | tf-07 … tf-14 | conventions, hub and spokes, DNS, policy, budget, logging, stack split |
| 2 Modules | tf-15 … tf-20 | extracted, versioned modules in their own repo |
| 3 Environments | tf-21 … tf-25 | dev/prod workloads, VMs, handover to the Ansible track |
| 4 Day two | tf-26 … tf-31 | import, refactor, drift, incidents, upgrades, team onboarding |

Before tf-01: run the lab inside WSL Ubuntu. tf-01 walks you through the tools, `az login`
and `./lab.sh init`.

## Conventions

Later tasks and their checks assume these. Keep them in your own code.

- **Version pins in every stack and module.** `required_version = "~> 1.17"` and
  `hashicorp/azurerm` `version = "~> 4.81"` (the latest 4.x minor on 2026-11-23). The lab
  stays on azurerm 4.x. Lock files (`.terraform.lock.hcl`) are committed from tf-30; the
  reference leaves them out before that.
- **Subscription ID in the provider block.** azurerm 4.x needs a subscription ID. Every stack
  sets it explicitly:

  ```hcl
  provider "azurerm" {
    subscription_id = "<your subscription id>"   # {{SUBSCRIPTION_ID}} in the reference files
    features {}
  }
  ```

  `./lab.sh pause`, `resume` and `nuke` run Terraform locally, and they must hit the same
  subscription as CI without anyone exporting `ARM_SUBSCRIPTION_ID` first. CI sets
  `ARM_SUBSCRIPTION_ID` too; the provider value is the same. A subscription ID is an
  identifier, not a secret. RBAC protects the subscription, so it's fine in a public repo.
- **State.** One `azurerm` backend per stack, all in `rg-<prefix>-tfstate` /
  `st<prefix>tfstate<suffix>` / container `tfstate`, keyed by stack name
  (`bootstrap.tfstate`, `landing-zone.tfstate`, …), always with `use_azuread_auth = true`.
  Shared keys are disabled on the account.
- **Stacks.** A stack is a directory under `terraform/` with an `azurerm` backend. The pipeline
  finds stacks on its own with `.github/scripts/stacks.sh`, a step in both the `plan` and the
  `apply` job; the workflow has exactly these two jobs. Stacks run in the order of
  `STACK_ORDER` in `.github/workflows/terraform.yml` (`landing-zone shared env-dev env-prod
  observability teams/payments`), then any others alphabetically. `bootstrap` is applied locally only:
  CI never manages its own identity.
- **Tags on every resource group.** `owner = "<your owner tag>"`, `env`, `managed_by =
  "terraform"`. The `env` values are `platform` (bootstrap: state and CI identity), `hub`
  (landing-zone hub and shared services), `dev` and `prod`.
- **Names** follow the table in the task texts (e.g. `rg-<prefix>-hub`, `vnet-<prefix>-hub`).
  Graders check names, locations, SKUs, tags and CIDRs literally. File layout is up to you.
- **Region** is `swedencentral` only (enforced by policy from tf-11).

## VM size

VMs use **`Standard_B2ats_v2`** (2 vCPU, 1 GiB, AMD, Basv2 series). It's the cheapest
current-generation x64 B-series size in swedencentral. Retail prices for Linux pay-as-you-go
in swedencentral, from the Azure Retail Prices API on 2026-11-23:

| Size | Series | USD/hour | Note |
|---|---|---|---|
| Standard_B1ls | Bv1 | 0.0054 | End of Life series with an announced retirement; not for new deployments |
| Standard_B2pts_v2 | Bpsv2 | 0.0086 | Arm64: needs arm64 images and tooling |
| **Standard_B2ats_v2** | Basv2 | **0.0097** | chosen |
| Standard_B2ts_v2 | Bsv2 | 0.0108 | Intel |

Sources: https://learn.microsoft.com/azure/virtual-machines/sizes/general-purpose/basv2-series,
https://learn.microsoft.com/azure/virtual-machines/sizes/general-purpose/bv1-series and
`https://prices.azure.com/api/retail/prices?$filter=serviceName eq 'Virtual Machines' and armRegionName eq 'swedencentral'`.
Availability in the lab subscription (`az vm list-skus -l swedencentral --size Standard_B2ats_v2`)
is verified live in Task 16, the live selftest.

## Cost

The lab is built to stay well under the Visual Studio credit (~500 kr/month):

| State | What runs | Approx. cost |
|---|---|---|
| Working | 3–5 small VMs, private endpoints, public IP, ACR Basic, Container Apps (scale to zero), Log Analytics with a daily cap | ~1–2 kr/hour |
| Paused | bootstrap + landing-zone only | ~20–30 kr/month |
| Nuked | nothing | 0 |

Phase 0 costs almost nothing: a state storage account (cents) plus free identities, role
assignments and empty resource groups.

**The pause rule:** as soon as VMs exist (phase 3), run `./lab.sh pause` whenever you stop for
the day, and `./lab.sh resume` when you come back. Pause destroys the expensive stacks
(shared, env-*, observability, teams/*) and keeps bootstrap and landing-zone. `./lab.sh cost`
shows month-to-date spend. The budget from tf-12 alerts at 80 % of 300 kr. `./lab.sh nuke`
removes everything, including the state account, when you're done.

Never used in the lab: Azure Firewall, Bastion, VPN Gateway, Application Gateway, Standard Load
Balancer, AKS or any premium SKU.
