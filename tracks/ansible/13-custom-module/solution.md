# an-13 solution

## Approach

A module that reads the JSON object, compares the one key as canonical JSON, and writes the file
atomically only when it changes and only outside check mode. `add_file_common_args` brings
owner, group and mode (check-mode aware) for free. Role `app_env` loops it over
`app_env_settings`; the inventory says what operations owns.

## Code

`ansible/library/acme_app_setting.py` (documentation blocks shortened here; the full module has
`DOCUMENTATION` with every option, `EXAMPLES` and `RETURN`):

```python
from __future__ import annotations

DOCUMENTATION = r"""
---
module: acme_app_setting
short_description: Manage one setting in an application's JSON settings file
options:
  path: {description: The JSON settings file, type: path, required: true}
  key: {description: The setting, dots nest, type: str, required: true}
  value: {description: Any JSON type, required when state=present, type: raw}
  state: {description: present or absent, type: str, choices: [present, absent], default: present}
extends_documentation_fragment:
  - ansible.builtin.files
"""
EXAMPLES = r"""..."""
RETURN = r"""..."""

import json, os, tempfile
from ansible.module_utils.basic import AnsibleModule

MISSING = object()

def as_json(v):
    return json.dumps(v, sort_keys=True)

def dump(d):
    return json.dumps(d, indent=2, sort_keys=True) + "\n"

def main():
    module = AnsibleModule(
        argument_spec=dict(
            path=dict(type="path", required=True),
            key=dict(type="str", required=True, no_log=False),
            value=dict(type="raw"),
            state=dict(type="str", default="present", choices=["present", "absent"]),
        ),
        required_if=[("state", "present", ["value"])],
        add_file_common_args=True,
        supports_check_mode=True,
    )
    p = module.params
    parts = p["key"].split(".")
    exists = os.path.exists(p["path"])
    data = json.load(open(p["path"])) if exists else {}
    before = dump(data) if exists else ""

    # walk to the parent object, creating it for state=present
    parent, previous = data, MISSING
    for part in parts[:-1]:
        parent = parent.setdefault(part, {}) if p["state"] == "present" else parent.get(part, {})
    previous = parent.get(parts[-1], MISSING)

    changed = False
    if p["state"] == "present" and (previous is MISSING or as_json(previous) != as_json(p["value"])):
        parent[parts[-1]] = p["value"]
        changed = True
    elif p["state"] == "absent" and previous is not MISSING:
        del parent[parts[-1]]
        changed = True

    result = dict(changed=changed, path=p["path"], key=p["key"],
                  previous=None if previous is MISSING else previous)
    if changed and module._diff:
        result["diff"] = dict(before=before, after=dump(data),
                              before_header=p["path"], after_header=p["path"])
    if changed and not module.check_mode:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p["path"]))
        with os.fdopen(fd, "w") as f:
            f.write(dump(data))
        module.atomic_move(tmp, p["path"], unsafe_writes=p["unsafe_writes"])
    if os.path.exists(p["path"]):
        result["changed"] = module.set_fs_attributes_if_different(
            module.load_file_common_arguments(p), result["changed"])
    module.exit_json(**result)

if __name__ == "__main__":
    main()
```

(The reference module also refuses a file that isn't a JSON object and a key whose parent isn't
an object, and cleans up its temporary file on errors.)

`ansible.cfg`, `[defaults]`: `library = ./library`.

`roles/app_env/tasks/main.yml`, added (defaults `app_env_settings: {}` and
`app_env_settings_path: /etc/acme/settings.json`, both in `meta/argument_specs.yml`):

```yaml
- name: Set the application settings that operations owns
  acme_app_setting:
    path: "{{ app_env_settings_path }}"
    key: "{{ item.key }}"
    value: "{{ item.value }}"
    owner: root
    group: "{{ app_env_group }}"
    mode: "0640"
  loop: "{{ app_env_settings | dict2items }}"
  loop_control:
    label: "{{ item.key }}"
```

Inventory: `acme_log_level: debug` in `env_dev.yml`, and in `role_web.yml`:

```yaml
app_env_settings:
  log_level: "{{ acme_log_level }}"
  features.maintenance_page: false
```

Molecule (`roles/app_env/molecule/default`): `ANSIBLE_LIBRARY:
${MOLECULE_PROJECT_DIRECTORY}/../../library` in `molecule.yml`'s `env`; `converge.yml` seeds the
file with a key the role doesn't own (`build`) and sets both settings; `verify.yml` asserts
`log_level == "debug"`, `features.maintenance_page is false` and that `build` survived.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-doc acme_app_setting | head -20
echo '{"build": "42"}' > /tmp/s.json
ansible localhost -i localhost, -c local -m acme_app_setting -a "path=/tmp/s.json key=a.b value=1" --check --diff
cat /tmp/s.json                               # unchanged
ansible localhost -i localhost, -c local -m acme_app_setting -a "path=/tmp/s.json key=a.b value=1"   # CHANGED
ansible localhost -i localhost, -c local -m acme_app_setting -a "path=/tmp/s.json key=a.b value=1"   # SUCCESS
(cd roles/app_env && molecule test)
ansible-lint && ansible-playbook site.yml && bin/drift-check.sh
ansible role_web -b -m ansible.builtin.command -a 'cat /etc/acme/settings.json'
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade`: the module on a scratch file on your machine, a `--check` run on a web VM that
must change nothing, the settings on both VMs, and a second `site.yml` run with `changed=0`.
