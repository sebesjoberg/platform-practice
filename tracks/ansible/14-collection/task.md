---
id: an-14
title: The collection acme.platform
target_minutes: 25
requires: [tf-25, an-13]
---
# an-14 The collection acme.platform

Two other teams want your `base` and `haproxy` roles, and the payments team wants
`acme_app_setting`. Copying directories between repos is how the last platform team ended up with
five slightly different `base` roles. The roles and the module become one versioned collection,
`acme.platform`, released by tag, and even this repo's own playbooks install a release instead of
reading whatever is on disk.

This task gets 25 minutes: moving five roles and a module, the metadata, and a first release.

## Deliverables

- [ ] The collection's source in your repo at
      `ansible/collections_src/ansible_collections/acme/platform/`:
  - [ ] `galaxy.yml`: namespace `acme`, name `platform`, version `1.0.0`, its dependencies
        (what the roles use) and a `build_ignore` that keeps the Molecule scenarios out of the
        installed collection
  - [ ] `meta/runtime.yml` (`requires_ansible`), a `README.md` and a `CHANGELOG.md`
  - [ ] the five roles under `roles/` (`base`, `app_env`, `acme_hello`, `nginx`, `haproxy`),
        moved with `git mv`, their Molecule scenarios still passing from there
  - [ ] the module under `plugins/modules/acme_app_setting.py`, called by its FQCN
        `acme.platform.acme_app_setting`
- [ ] Nothing left in `ansible/roles/` or `ansible/library/`: one copy of each role.
- [ ] The release: tag `acme.platform-1.0.0` on a commit of `main` that holds this source, pushed
      to GitHub.
- [ ] `collections/requirements.yml` installs it from git by that tag (the `#/` subdirectory of
      your repo, `type: git`, `version: acme.platform-1.0.0`), into `ansible/collections` like the
      others.
- [ ] `site.yml` and `rolling.yml` use the roles by FQCN (`acme.platform.base`, ...).
- [ ] Lint-clean (ansible-lint checks the collection's metadata too); a second `site.yml` run
      reports `changed=0`.

## Done when

`ansible-galaxy collection list acme.platform` (from `ansible/`) shows `1.0.0` under
`ansible/collections`, `ansible-doc acme.platform.acme_app_setting` works, `molecule test` passes
in `collections_src/ansible_collections/acme/platform/roles/base`, `ansible-playbook site.yml`
reports `changed=0`, and `./lab.sh grade` passes.
