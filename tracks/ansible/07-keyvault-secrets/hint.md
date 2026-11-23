# an-07 hints

Docs:
- The Key Vault secret lookup (`vault_url`, `auth_source`, `use_msi`): https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_keyvault_secret_lookup.html
- `no_log` and what it hides: https://docs.ansible.com/ansible/latest/reference_appendices/logging.html#protecting-sensitive-data-with-no-log
- Variable precedence (why `-e` beats group_vars): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence
- Key Vault RBAC roles: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide

Traps:
- **The lookup tries the VM metadata endpoint first** (`use_msi` defaults to true), with a 3-second
  connect timeout, on every call. On your machine that is dead time before it falls back to
  `auth_source`. Pass `use_msi` derived from your auth variable (`msi` → true, else false).
- **Lookups run on the control node**, not on the VM: your `az login` reads the vault, the web
  VMs never talk to Key Vault here. Later, on the runner, the jump host's identity does.
- **Variables are templated lazily.** A lookup in `group_vars` runs each time the variable is
  used, per host. Use it in one place (the template) and it runs once per host.
- **`no_log` on the template task hides the diff too**; without it, `--check --diff` (drift
  detection, CI) prints old and new value into a public job log. `debug: var=` of the variable
  prints it, whatever the task says. Role argument specs can mark an option `no_log: true` as
  well: the argument check templates the value.
- **`vault_url` without a trailing slash** (`https://kv-{{PREFIX}}-dev-{{SUFFIX}}.vault.azure.net`):
  the MSI code path appends `/secrets/<name>` to it.
- **`git grep` searches your working tree, not history.** Once a value is committed and pushed
  to a public repo, it is leaked: deleting the line doesn't help, rotating the secret does
  (`az keyvault secret set`, then `site.yml`). The grader checks every branch's history.
- **A `log_path` in `ansible.cfg`** keeps every run's output on disk: one task without `no_log`
  and the value is in that file.
- **Molecule has no Key Vault.** Keep the lookup in the inventory and pass plain values into the
  role; `converge.yml` then sets a stub.
