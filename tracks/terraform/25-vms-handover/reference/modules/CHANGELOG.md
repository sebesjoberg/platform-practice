# Changelog

Notable changes to the modules in this repo. A version is a git tag `vX.Y.Z` on `main`
(semantic versioning): a new major version means callers have to change something, and its
entry says what.

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
