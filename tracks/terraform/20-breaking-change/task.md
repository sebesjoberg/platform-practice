---
id: tf-20
title: A breaking change, dev first
target_minutes: 20
requires: [tf-19]
---
# tf-20 A breaking change, dev first

The spoke module's `address_space` input takes one CIDR block, but Azure's `address_space` is a
list, and the payments team has already passed `["10.3.0.0/16"]` twice. The CTO approves the
rename to `vnet_cidr`. Renaming an input breaks every caller, so it's a new major version, and
it rolls out like any risky change: dev first, prod later.

## Deliverables

In `{{MODULES_REPO}}`:

- [ ] `spoke`'s input `address_space` becomes `vnet_cidr`: same type, same validation. Update
      the module code, its tests and the generated README section.
- [ ] `CHANGELOG.md` at the repo root with a `2.0.0` entry: what breaks and how a caller
      migrates. Add a `1.0.0` entry for the first release too.
- [ ] CI green on `main`, then an annotated tag `v2.0.0`, pushed. `v1.0.0` stays where it is.

In `{{LIVE_REPO}}`:

- [ ] `env-dev` uses `?ref=v2.0.0` and passes `vnet_cidr`. Its own variable stays
      `address_space`: the stack's interface is not the module's.
- [ ] `env-prod` stays on `?ref=v1.0.0`, unchanged.
- [ ] One PR. Both env stacks plan `No changes.` Merge it.

## Done when

`./lab.sh grade` passes: the module has `vnet_cidr`, the changelog has its `2.0.0` entry, tag
`v2.0.0` exists with the rename while `v1.0.0` still has `address_space`, dev pins v2 and prod
v1, and the run on `main` is green.

Target: 20 minutes.
