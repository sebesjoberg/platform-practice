#!/usr/bin/python
# -*- coding: utf-8 -*-
# Copyright: Acme platform team
# GNU General Public License v3.0+ (see https://www.gnu.org/licenses/gpl-3.0.txt)
from __future__ import annotations

DOCUMENTATION = r"""
---
module: acme_app_setting
short_description: Manage one setting in an application's JSON settings file
version_added: "1.0.0"
description:
  - Sets or removes one key in a JSON settings file and leaves every other key as it is, so that
    several owners can share the file. The app team's release tooling writes some keys,
    operations others.
  - Nested keys are written with dots. C(features.maintenance_page) is the key
    C(maintenance_page) in the object C(features).
  - Writes atomically, and only when the value really changes (compared as JSON, so C(1) and
    C(true) are different values).
options:
  path:
    description:
      - The JSON settings file. It must hold a JSON object.
      - Created (with only this key) when it is missing and O(state=present).
    type: path
    required: true
  key:
    description:
      - The setting. Dots separate the levels of nested objects.
    type: str
    required: true
  value:
    description:
      - The value, any JSON type (string, number, boolean, list, object, null).
      - Required when O(state=present). Strings stay strings, so pass numbers and booleans as
        YAML values, not as C(key=value) text.
    type: raw
  state:
    description:
      - V(present) sets the key to O(value), V(absent) removes it (its parents stay).
    type: str
    choices: [present, absent]
    default: present
extends_documentation_fragment:
  - ansible.builtin.files
attributes:
  check_mode:
    support: full
    description: Reports what would change and writes nothing.
  diff_mode:
    support: full
    description: Shows the file before and after, as sorted, indented JSON.
author:
  - Acme platform team
"""

EXAMPLES = r"""
- name: Log at debug level
  acme_app_setting:
    path: /etc/acme/settings.json
    key: log_level
    value: debug
    owner: root
    group: acme
    mode: "0640"

- name: A nested feature flag (a real boolean, not the string "false")
  acme_app_setting:
    path: /etc/acme/settings.json
    key: features.maintenance_page
    value: false

- name: Remove a setting nobody uses any more
  acme_app_setting:
    path: /etc/acme/settings.json
    key: legacy.cache_size
    state: absent
"""

RETURN = r"""
path:
  description: The settings file.
  returned: always
  type: str
  sample: /etc/acme/settings.json
key:
  description: The setting, as given.
  returned: always
  type: str
  sample: features.maintenance_page
value:
  description: The value the key has now (or would have, in check mode).
  returned: when O(state=present)
  type: raw
  sample: false
previous:
  description: The value before this task, null when the key was missing.
  returned: always
  type: raw
  sample: true
"""

import json
import os
import tempfile

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.common.text.converters import to_native

MISSING = object()


def as_json(value):
    """Canonical JSON text of a value, so 1, true and "1" compare as different values."""
    return json.dumps(value, sort_keys=True)


def dump(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def get_key(data, parts):
    cur = data
    for part in parts:
        if not isinstance(cur, dict) or part not in cur:
            return MISSING
        cur = cur[part]
    return cur


def set_key(module, data, parts, value):
    cur = data
    for i, part in enumerate(parts[:-1]):
        nxt = cur.get(part, MISSING)
        if nxt is MISSING:
            nxt = cur[part] = {}
        elif not isinstance(nxt, dict):
            module.fail_json(msg="cannot set %s: %s is not an object" % (".".join(parts), ".".join(parts[: i + 1])))
        cur = nxt
    cur[parts[-1]] = value


def del_key(data, parts):
    cur = data
    for part in parts[:-1]:
        cur = cur[part]
    del cur[parts[-1]]


def write_atomic(module, path, text):
    fd, tmp = tempfile.mkstemp(prefix=".acme_app_setting.", dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        module.atomic_move(tmp, path, unsafe_writes=module.params["unsafe_writes"])
    except Exception as e:
        if os.path.exists(tmp):
            os.unlink(tmp)
        module.fail_json(msg="cannot write %s: %s" % (path, to_native(e)))


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
    path = module.params["path"]
    key = module.params["key"]
    state = module.params["state"]
    parts = key.split(".")
    if not all(parts):
        module.fail_json(msg="key %r has an empty part" % key)

    exists = os.path.exists(path)
    data = {}
    if exists:
        try:
            with open(path) as f:
                data = json.load(f)
        except ValueError as e:
            module.fail_json(msg="%s is not valid JSON: %s" % (path, to_native(e)))
        if not isinstance(data, dict):
            module.fail_json(msg="%s does not hold a JSON object" % path)
    before = dump(data) if exists else ""

    previous = get_key(data, parts)
    result = dict(changed=False, path=path, key=key, previous=None if previous is MISSING else previous)

    if state == "present":
        value = module.params["value"]
        result["value"] = value
        if previous is MISSING or as_json(previous) != as_json(value):
            set_key(module, data, parts, value)
            result["changed"] = True
    elif previous is not MISSING:
        del_key(data, parts)
        result["changed"] = True

    if result["changed"]:
        if module._diff:
            result["diff"] = dict(before=before, after=dump(data), before_header=path, after_header=path)
        if not module.check_mode:
            write_atomic(module, path, dump(data))

    # Owner, group and mode, when the file is there (in check mode a new file isn't).
    if os.path.exists(path):
        file_args = module.load_file_common_arguments(module.params)
        result["changed"] = module.set_fs_attributes_if_different(file_args, result["changed"])

    module.exit_json(**result)


if __name__ == "__main__":
    main()
