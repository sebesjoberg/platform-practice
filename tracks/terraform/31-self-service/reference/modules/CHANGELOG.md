# Changelog

Notable changes to the modules in this repo. A version is a git tag `vX.Y.Z` on `main`
(semantic versioning): a new major version means callers have to change something, and its
entry says what.

## 3.1.0 (2026-11-23)

### Added

- `team-env`: new module. Onboards one product team inside the resource group the platform vended
  for it (input `resource_group_name`; the module doesn't create the group): CI identity
  `id-<prefix>-<team>-ci` with a federated credential `gh-main` for the team repo's main branch
  (immutable subject, looked up in GitHub's API), `Contributor` on the team's group only, and a
  monthly budget `budget-<prefix>-<team>` with alerts at 80 % actual and 100 % forecast. Needs the
  `hashicorp/http` provider.

`spoke`, `app-env` and `linux-vm` are unchanged: callers on `v3.0.0` need not move.

## 3.0.0 (2026-11-23)

### Breaking

- Every module now needs **azurerm 5.x**: `version = ">= 5.14, < 6.0"` (was `>= 4.81, < 5.0`).
  A stack on azurerm 4.x can't use this release; one on 5.x can't use 2.x. A provider major
  is a breaking change for every caller, even where a module's own code didn't change.
- `spoke`: the input `private_dns_zone_names` (a set of zone names in the hub resource group) is
  replaced by `private_dns_zone_ids`, a map of zone name to the zone's resource ID. azurerm 5.0
  removed `resource_group_name` and `private_dns_zone_name` from
  `azurerm_private_dns_zone_virtual_network_link`; a link names its zone by ID only.

### Migration from 2.x

1. Move the calling stack to azurerm 5.x first (`version = "~> 5.14"`; read the provider's 5.0
   upgrade guide for the stack's own resources), and lock it for every platform you run on.
2. Change every module source's `?ref=` to `v3.0.0`. All modules of one stack move together:
   `terraform init` fails if any module still caps azurerm below 5.0.
3. In the `spoke` call, replace `private_dns_zone_names = keys(data.azurerm_private_dns_zone.hub)`
   with `private_dns_zone_ids = { for name, zone in data.azurerm_private_dns_zone.hub : name => zone.id }`.
4. Plan. Expect `No changes.`: the link addresses (keyed by zone name) and their Azure IDs are
   the same; the provider fills in `private_dns_zone_id` from the link's ID when it reads it.

`spoke` also sets `default_outbound_access_enabled = true` on its subnets explicitly (no change
in Azure: it was the provider's default; now a changed default can't cut the VMs off from apt).
`app-env` and `linux-vm` change only their provider range.

## 2.2.0 (2026-11-23)

### Added

- `linux-vm`: new module. One Ubuntu 24.04 LTS VM (`Standard_B2ats_v2` by default, B-series
  only), SSH key only, a NIC in the given subnet, and optionally a Standard static public IP
  (`public_ip_name`) and a system-assigned identity (`system_assigned_identity`). Outputs
  `private_ip_address`, `public_ip_address` and `principal_id` for role assignments.

`spoke` and `app-env` are unchanged.

## 2.1.0 (2026-11-23)

### Added

- `app-env`: new module. One environment's app identity `id-<prefix>-app-<env>` and Key Vault
  `kv-<prefix>-<env>-<suffix>` (RBAC, 7 days of soft delete, no purge protection) with a
  private endpoint `pe-kv-<prefix>-<env>` and a DNS zone group, `Key Vault Secrets User` for the
  app and `Key Vault Secrets Officer` for the identity that runs Terraform, and an optional
  `secrets` map it writes into the vault. Needs the `hashicorp/time` provider.
- `.trivyignore.yaml`: the scan in CI accepts the vault's public network access (see the file).

`spoke` is unchanged: callers on `v2.0.0` need not move.

## 2.0.0 (2026-11-23)

### Breaking

- `spoke`: the input `address_space` is renamed to `vnet_cidr`. It always took one CIDR block,
  while Azure's `address_space` is a list, so the old name invited `["10.1.0.0/16"]`. Same type
  (`string`), same validation (a /16).

### Migration from 1.x

1. Change the module source's `?ref=` to `v2.0.0`.
2. Rename the argument in the module call: `address_space = …` becomes `vnet_cidr = …`, with the
   same value.
3. Plan. Expect `No changes.`: no resource address or attribute changes, so nothing in the state
   or in Azure does either.

Roll it out one environment at a time: dev first, prod once dev has run on 2.0.0 without
surprises. Until then prod stays on `v1.0.0`, which doesn't change.

## 1.0.0 (2026-11-23)

- `spoke`: first release, the spoke module as extracted from the platform repo: resource group,
  VNet with `snet-app`, `snet-pe` and `snet-aca`, NSGs, both hub peerings and the private DNS
  zone links. Inputs `env`, `address_space`, `prefix`, `location`, `owner`, `hub`,
  `private_dns_zone_names`; outputs `resource_group_name`, `vnet_id`, `vnet_name`,
  `subnet_ids`.
