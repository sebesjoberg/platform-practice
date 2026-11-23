# an-04 hints

Docs:
- ansible-lint profiles and configuration: https://docs.ansible.com/projects/lint/profiles/ and https://docs.ansible.com/projects/lint/configuring/
- The `yaml` rule and the yamllint settings ansible-lint requires: https://docs.ansible.com/projects/lint/rules/yaml/
- yamllint configuration: https://yamllint.readthedocs.io/en/stable/configuration.html
- pre-commit (`rev`, `language_version`, `additional_dependencies`, `--config`): https://pre-commit.com/

Traps:
- **What the production profile finds** in typical role code: `var-naming[no-role-prefix]` (every
  role variable, registered ones too, starts with `base_`), `fqcn` (`ansible.builtin.apt`, not
  `apt`), `name[casing]`, `no-changed-when`, `risky-file-permissions` (set `mode:` on every file),
  `schema[meta]` (role metadata needs `galaxy_info` with platforms and `min_ansible_version` as a
  string).
- **The ansible-lint hook asks for Python 3.14** (`language_version` in its hook definition); WSL
  Ubuntu 24.04 has 3.12. Override `language_version` in your config, and pin
  `additional_dependencies` to the same `ansible-core` as `requirements.txt`, or the hook lints
  with whatever ansible-core is newest that day.
- **pre-commit runs hooks from the repo root**, not from `ansible/`. Point ansible-lint at the
  project (`--project-dir ansible -c ansible/.ansible-lint`, e.g. through the hook's `entry`), give
  yamllint `-c ansible/.yamllint`, and limit both with `files: ^ansible/`: the Terraform workflows
  are not Ansible.
- **A config outside the repo root** needs `--config ansible/.pre-commit-config.yaml` for
  `pre-commit install` and `pre-commit run` alike.
- **ansible-lint needs the collections** to resolve `community.general.timezone` and friends. It
  installs `collections/requirements.yml` into its cache (`ansible/.ansible/`, gitignore it) on the
  first run; offline it uses what `ansible.cfg` points at.
- **ansible-lint runs yamllint rules too** (the `yaml` rule), with your `.yamllint` when present.
  A `.yamllint` that contradicts ansible-lint's needs (comment spacing, octal values, `truthy`) is
  reported as incompatible.
- **`# noqa` without a reason** is how lint gates rot. Write why on the same line.
