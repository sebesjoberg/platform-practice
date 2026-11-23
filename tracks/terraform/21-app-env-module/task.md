---
id: tf-21
title: An app environment module
target_minutes: 25
requires: [tf-20]
---
# tf-21 An app environment module

The first product team wants to ship a service to dev next week, and prod soon after. They need
an identity to run as and a place for secrets, and the CTO wants prod to get exactly what dev
gets. So it's a module, released from the modules repo like `spoke`.

This task gets 25 minutes: a module with five kinds of resources, its release, and a bootstrap
change before the platform PR. The starters take care of the parts that aren't the lesson.

`./lab.sh next` has saved starters in `~/.platform-lab/starter/tf-21/` (it printed the copy
commands):

- `modules/app-env/`: `versions.tf`, `variables.tf`, `outputs.tf` and
  `tests/app-env.tftest.hcl`. The tests describe what the module must do. You write `main.tf`.
  `cp -rn ~/.platform-lab/starter/tf-21/modules/app-env "$MODULES_DIR/"`
- `modules/.trivyignore.yaml` (the vault's public access, AZU-0013, accepted with its reason)
  and `modules/.github/workflows/ci.yml` (tf-19's CI, now passing that file to trivy). Copy both
  over the modules repo's versions.
- `live/terraform/bootstrap/platform-owner.tf`: gives you `Key Vault Secrets Officer` on the
  subscription. Being Owner gives you no access to secrets in an RBAC vault, and
  `./lab.sh pause` deletes them as you.

## Deliverables

In `{{MODULES_REPO}}`, module `app-env/main.tf`, every resource in `var.resource_group_name`
with the tags `owner`, `env`, `managed_by = "terraform"`:

- [ ] User-assigned identity `id-{{PREFIX}}-app-{env}`.
- [ ] Key Vault `kv-{{PREFIX}}-{env}-{{SUFFIX}}`: SKU `standard`, RBAC authorization (no access
      policies), `soft_delete_retention_days = 7`, purge protection off, public network
      access enabled.
- [ ] Private endpoint `pe-kv-{{PREFIX}}-{env}` in `var.private_endpoint_subnet_id`,
      sub-resource `vault`, with a DNS zone group for `privatelink.vaultcore.azure.net`
      (`var.key_vault_dns_zone_id`).
- [ ] Role assignments on the vault: `Key Vault Secrets User` for the identity, and
      `Key Vault Secrets Officer` for whoever runs Terraform (`azurerm_client_config`).
- [ ] `var.secrets` written as Key Vault secrets, but only after the role assignments have had
      time to reach the data plane: a `time_sleep` of 120 seconds between them.
- [ ] `terraform test` passes and the README's generated section is up to date.

Also in `{{MODULES_REPO}}`: the starter's `.trivyignore.yaml` and `ci.yml`, `app-env` in the
root README's module table and a `2.1.0` entry in `CHANGELOG.md`. CI green on `main`, then tag
`v2.1.0` and push it.

In `{{LIVE_REPO}}`:

- [ ] `terraform/bootstrap`: add `Key Vault Secrets Officer`
      (`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`) to the roles the CI identity may assign, and add
      the starter's `platform-owner.tf`. Apply bootstrap locally, before the PR below.
- [ ] `terraform/env-dev`: `module "app_env"` from `//app-env?ref=v2.1.0` (spoke stays on
      `v2.0.0`), a variable `suffix` (default `{{SUFFIX}}`), and one secret
      `greeting = "Hello from {{PREFIX}} dev"`. The provider block gets
      `features { key_vault { purge_soft_delete_on_destroy = true } }`; pin `hashicorp/time`
      to `~> 0.14`.
- [ ] The plan job's trivy step adds `--tf-exclude-downloaded-modules`: trivy downloads the
      modules you pin, and their findings belong to the modules repo's CI.
- [ ] One PR, merged, applied by the pipeline.

## Done when

`az keyvault show -n kv-{{PREFIX}}-dev-{{SUFFIX}}` shows RBAC on and 7 retention days,
`az keyvault secret show --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n greeting --query value`
prints the greeting, and `./lab.sh grade` passes.

Target: 25 minutes.
