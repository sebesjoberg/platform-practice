# an-13 hints

Docs:
- Developing modules (`AnsibleModule`, `exit_json`, `fail_json`): https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general.html
- Module documentation blocks: https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_documenting.html
- Check mode and diff support in modules: https://docs.ansible.com/ansible/latest/dev_guide/developing_program_flow_modules.html#check-mode
- Where Ansible finds local modules (`library`, `ANSIBLE_LIBRARY`): https://docs.ansible.com/ansible/latest/dev_guide/developing_locally.html

Traps:
- **Check mode is your job.** `supports_check_mode=True` only tells Ansible not to skip the module;
  computing `changed` and *then* not writing when `module.check_mode` is set is up to you.
- **Diff mode is `module._diff`**: return `diff=dict(before=..., after=..., before_header=path,
  after_header=path)` with the whole file rendered the same way both times (sorted keys, fixed
  indent), or the diff is noise.
- **Compare values as JSON**, not with `==`: in Python `True == 1`, so a naive comparison never
  notices `1` replacing `true`. `json.dumps(v, sort_keys=True)` on both sides does.
- **`value` is `type="raw"`**, so YAML types arrive as they are (`false` is a boolean). From
  `-a "key=x value=1"` on the command line everything is a string; that is fine for testing.
- **Owner, group and mode for free:** `add_file_common_args=True` in the `AnsibleModule` call,
  then `module.set_fs_attributes_if_different(module.load_file_common_arguments(module.params),
  changed)`. It respects check mode on its own. In the docs, `extends_documentation_fragment:
  [ansible.builtin.files]` documents those options.
- **Write atomically**: a temporary file in the same directory, then `module.atomic_move()`. A
  half-written JSON file is worse than none.
- **DOCUMENTATION is YAML inside a Python string**: an unquoted `: ` in a description breaks it.
  `ansible-doc acme_app_setting` is the test.
- **The module isn't next to the Molecule playbook.** `ansible.cfg`'s `library` doesn't apply in
  Molecule (it uses its own config): add `ANSIBLE_LIBRARY` to the scenario's `env`.
- **A module from `library/`** has no collection, so its name is just `acme_app_setting` in tasks.
  In an-14 it gets a FQCN.
