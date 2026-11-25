---
id: an-13
title: A custom module with check mode
target_minutes: 25
requires: [tf-25, an-12]
---
# an-13 A custom module with check mode

The app team's next release reads its settings from `/etc/acme/settings.json`, and their release
tooling writes some of the keys (the build number, their feature flags). Operations owns others:
the log level per environment and the maintenance switch. A template would own the whole file
and wipe their keys on every run; `lineinfile` on JSON is a bug waiting to happen. You write a
module that manages **one key** and leaves the rest alone, and it has to behave like a real
Ansible module: documented, idempotent, honest in check mode (an-12's drift check relies on that).

This task gets 25 minutes: a module with its documentation, and a role change that uses it.

## Deliverables

- [ ] Module `acme_app_setting` in `ansible/library/acme_app_setting.py` (an-14 moves it into a
      collection), Python standard library plus `ansible.module_utils` only:
  - [ ] options `path` (the JSON file, created when missing), `key` (dots nest:
        `features.maintenance_page`), `value` (any JSON type), `state` (`present`/`absent`), and
        the usual `owner`/`group`/`mode` of a file
  - [ ] `supports_check_mode=True`: in check mode it reports what would change and writes nothing
  - [ ] diff mode: `--diff` shows the file before and after
  - [ ] idempotent: `changed` only when the value really differs (`1`, `"1"` and `true` are three
        different values); other keys survive; the write is atomic
  - [ ] `DOCUMENTATION`, `EXAMPLES` and `RETURN` blocks, so `ansible-doc acme_app_setting` works
- [ ] `ansible.cfg` finds it (`library`), and role `app_env` uses it: a new role variable
      `app_env_settings` (key → value) applied to `/etc/acme/settings.json`, owner `root`, group
      `acme`, mode `0640`. The role's Molecule scenario still passes and checks the settings.
- [ ] The inventory: `log_level` = `debug` (from a per-environment variable in `env_dev.yml`) and
      `features.maintenance_page` = `false` (a boolean).
- [ ] Lint-clean; a second `site.yml` run reports `changed=0`.

## Done when

`ansible-doc acme_app_setting` shows your documentation; on a web VM
`sudo cat /etc/acme/settings.json` shows both keys;
`ansible vm-{{PREFIX}}-web-dev-1 -b -m acme_app_setting -a "path=/etc/acme/settings.json key=x value=1" --check --diff`
reports `CHANGED` with a diff and leaves the file as it was, and `./lab.sh grade` passes.
