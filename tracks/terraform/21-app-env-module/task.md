---
id: tf-21
title: An app environment module
target_minutes: 20
requires: [tf-20]
---
# tf-21 An app environment module

The first product team wants to ship a service to dev next week, and prod soon after. They need
an identity to run as and a place for secrets, and the CTO wants prod to get exactly what dev
gets. So it's a module, released from the modules repo like `spoke`.

`./lab.sh next` has saved a starter in `~/.platform-lab/starter/tf-21/app-env/`:
`versions.tf`, `variables.tf`, `outputs.tf` and `tests/app-env.tftest.hcl`. Copy it into the
modules repo (`cp -rn ~/.platform-lab/starter/tf-21/app-env "$MODULES_DIR/"`). The tests
describe what the module must do. You write `main.tf`.

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

Also in `{{MODULES_REPO}}`: `app-env` in the root README's module table, a `2.1.0` entry in
`CHANGELOG.md`, and a `.trivyignore.yaml` that accepts `AZU-0013` (public network access) for
`app-env/main.tf` only, with the reason. CI passes it to trivy (`--ignorefile`). CI green on
`main`, then tag `v2.1.0` and push it.

In `{{LIVE_REPO}}`:

- [ ] `terraform/bootstrap`: add `Key Vault Secrets Officer`
      (`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`) to the roles the CI identity may assign, and give
      yourself `Key Vault Secrets Officer` on the subscription. Apply bootstrap locally.
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

Target: 20 minutes.
