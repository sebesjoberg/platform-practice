# tf-30 hints

Docs:
- azurerm 5.0 upgrade guide: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide
- Dependency lock file: https://developer.hashicorp.com/terraform/language/files/dependency-lock
- `terraform providers lock`: https://developer.hashicorp.com/terraform/cli/commands/providers/lock
- Dependabot options (`package-ecosystem: terraform`, `directories`, `groups`): https://docs.github.com/code-security/dependabot/working-with-dependabot/dependabot-options-reference

Traps:
- **What 5.0 changes for this code:**
  - *Resource provider registration.* 4.x registered about 60 resource providers at every run;
    5.x registers none. Your subscription already has what the lab uses, but a fresh one would
    fail with `MissingSubscriptionRegistration` (Container Apps, for one). Each stack lists its
    own in `resource_providers_to_register` (the starters have the lists).
  - *`azurerm_private_dns_zone_virtual_network_link`* lost `resource_group_name` and
    `private_dns_zone_name`; it takes `private_dns_zone_id`. That's landing-zone's hub links and
    the spoke module's links, so `spoke` gets a new input: a map of zone name to zone ID. Keep
    the zone **names** as the `for_each` keys and the state addresses stay the same.
  - Things that don't affect you, but check: `azurerm_key_vault` now requires
    `rbac_authorization_enabled` (app-env has it), `azurerm_storage_account` defaults
    `allow_nested_items_to_be_public` to `false` (both accounts set it), the Container Apps
    environment's `logs_destination` is no longer computed. Nothing in the guide forces a
    replacement of the VMs, NICs, public IP or vaults.
- **Order matters.** A stack on 5.x can't use a module capped `< 5.0`: `terraform init` fails.
  So the modules release `v3.0.0` first, then the platform PR moves the pins and the refs
  together.
- **Lock files are per platform.** `terraform init` on Linux records only the Linux hashes; the
  same lock file then fails on a Windows teammate's machine (or WSL's Windows side) with
  `the current package doesn't match any of the checksums`. `providers lock -platform=... -platform=...`
  records both. Modules never commit lock files: the calling stack locks.
- **Run it in each stack directory,** after `terraform init -upgrade` (which fetches the module
  sources at their new refs).
- **`directories` lists stacks, not modules.** Dependabot's `terraform` ecosystem updates the
  provider constraints, the lock files and the `git::...?ref=` tags of module sources in each
  listed directory. Modules live in their own repo with their own release process.
- **Dependabot PRs get Dependabot secrets, not Actions secrets.** Without `BUDGET_EMAIL` and
  `LEARNER_IP` as Dependabot secrets, every Dependabot PR's plan fails the variable validation,
  and the required `plan` check blocks it. Same values as the repo secrets; a secret can't be
  read back, so set them from the source.
- **bootstrap is applied by you, never by CI.** After the merge, run it locally with the new
  provider so its state is written by 5.x too.
- **Canary?** A cautious team moves env-dev first and env-prod a week later (two PRs), as in
  tf-20. For a provider upgrade whose plan is `No changes.` everywhere, one PR is fine.
