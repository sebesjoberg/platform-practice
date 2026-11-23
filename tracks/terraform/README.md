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

- **Version pins in every stack and module.** Stacks: `required_version = "~> 1.17"` and
  `hashicorp/azurerm` `version = "~> 4.81"` (the latest 4.x minor on 2026-11-23). Modules
  (from tf-16) state the range they work with instead: `required_version = ">= 1.17"` and
  azurerm `version = ">= 4.81, < 5.0"`; the calling stack's pin decides what runs. The lab
  stays on azurerm 4.x (5.x exists and breaks the lab's code). Stacks commit lock files
  (`.terraform.lock.hcl`) from tf-30, and the reference leaves them out before that; modules
  never do.
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
  `apply` job. Stacks run in the order of
  `STACK_ORDER` in `.github/workflows/terraform.yml` (`landing-zone shared env-dev env-prod
  observability teams/payments`), then any others alphabetically. `bootstrap` is applied locally only:
  CI never manages its own identity. Nothing under `terraform/modules/` is ever a stack (tf-15).
- **Jobs.** `plan` (pull requests) plans every stack and is the required status check (tf-06),
  so it never `needs:` another job: a job it waited for could fail and leave it skipped, and a
  skipped required check counts as passed. `apply` (pushes to `main`, manual runs) applies the
  selected stacks. From tf-24 `apply` skips `env-prod`, and a third job `apply-prod`
  (`needs: apply`, `environment: prod`) applies it after the `prod` environment's reviewer
  approves; its OIDC subject `…:environment:prod` matches the credential `gh-env-prod`.
- **Modules.** The `spoke` module lives in `terraform/modules/spoke` from tf-15, and from tf-19
  in your public modules repo `<prefix>-terraform-modules` (directory `spoke/`, cloned to
  `MODULES_DIR`). Stacks call it as `module "spoke"`, so state addresses stay `module.spoke.*`
  wherever the code lives, and pin a release:
  `git::https://github.com/<owner>/<prefix>-terraform-modules.git//spoke?ref=vX.Y.Z`. Released
  tags never move; a breaking change is a new major version with a `CHANGELOG.md` entry (tf-20).
  Module tests (`terraform test`, mock providers only) run in the plan job until tf-19, then in
  the modules repo's CI. A release tags the whole repo: `app-env` arrives in `v2.1.0` (tf-21),
  `linux-vm` in `v2.2.0` (tf-25), and a stack may pin different releases for different modules
  (`module "app_env"`, `module "jump"`, `module "web"`). The modules repo's CI scans its modules
  with trivy; the platform repo's scan skips downloaded modules (`--tf-exclude-downloaded-modules`).
- **Tags on every resource group.** `owner = "<your owner tag>"`, `env`, `managed_by =
  "terraform"`. The `env` values are `platform` (bootstrap: state and CI identity), `hub`
  (landing-zone hub and shared services), `dev` and `prod`. VMs also carry `role` (`jump`,
  `web`) and `env` (`hub`, `dev`): the Ansible track's dynamic inventory groups by them.
- **Inputs.** From tf-07 stacks declare validated variables with the lab values as defaults,
  so CI needs no tfvars file (`*.tfvars` is gitignored and the repo is public). The one
  personal value, the budget alert address, is the repo variable `BUDGET_EMAIL`, which the
  workflow passes as `TF_VAR_budget_email` (tf-12). From tf-25 two more: `LEARNER_IP` (your
  public IP, the only SSH source for the jump VM; `sensitive = true`) and `SSH_PUBLIC_KEY` (the
  public half of `~/.ssh/<prefix>_lab`; the private key never goes into a repo), passed as
  `TF_VAR_learner_ip` and `TF_VAR_ssh_public_key`. Export the `TF_VAR_*` values in your shell
  before running those stacks locally (`./lab.sh pause` and `nuke` fill in harmless values).
- **Workloads.** Each environment's identity and Key Vault come from the `app-env` module
  (tf-21). Vaults use RBAC, 7 days of soft delete and no purge protection, and the env stacks
  set `features { key_vault { purge_soft_delete_on_destroy = true } }` so pause/resume can
  reuse the names. CI writes secrets with `Key Vault Secrets Officer` on each vault; you hold
  that role on the subscription (bootstrap) so local destroys can delete them. Whoever consumes
  a shared service grants access in its own stack: env stacks assign `AcrPull` on the shared
  registry and `Key Vault Secrets User` on their vault for the jump VM.
- **Stacks share through Azure, not state.** From tf-14 the `env-dev` / `env-prod` stacks
  find the hub with data sources (by name), never with `terraform_remote_state`.
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

Phase 3 at full size (tf-25), retail USD per hour in swedencentral:

| What | USD/hour |
|---|---|
| 3 × `Standard_B2ats_v2` (jump, web-dev-1, web-dev-2) | 0.029 |
| 3 × Standard HDD OS disk (30 GiB) | ~0.006 |
| `pip-<prefix>-jump` (Standard, static) | 0.005 |
| 2 × private endpoint (Key Vault, dev and prod) | 0.02 |
| ACR Basic | 0.007 |
| Container Apps (Consumption profile, scale to zero) | ~0 while idle |
| Container Apps ingress public IP in `ME_cae-<prefix>-dev`, if billed | 0.005 |

About 0.07 USD (~0.75 kr) an hour. The web VMs reach the internet (apt) through the spoke
subnets' default outbound access, which costs nothing. Azure no longer turns it on by default
for new VNets, but the azurerm provider creates subnets with
`default_outbound_access_enabled = true`, which Azure still accepts. A NAT gateway, the
production answer, would cost 0.045 USD an hour plus data, more than all three VMs together.

Two things the pipeline can't do alone after `./lab.sh pause`: the new registry is empty, so
`./lab.sh resume` applies `shared` first and imports the app image before the full run; and
`apply-prod` waits for your approval.

**The pause rule:** as soon as VMs exist (phase 3), run `./lab.sh pause` whenever you stop for
the day, and `./lab.sh resume` when you come back. Pause destroys the expensive stacks
(shared, env-*, observability, teams/*) and keeps bootstrap and landing-zone. `./lab.sh cost`
shows month-to-date spend. The budget from tf-12 alerts at 80 % of 300 kr. `./lab.sh nuke`
removes everything, including the state account, when you're done.

Never used in the lab: Azure Firewall, Bastion, VPN Gateway, Application Gateway, Standard Load
Balancer, AKS or any premium SKU.
