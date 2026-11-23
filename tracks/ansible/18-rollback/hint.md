# an-18 hints

Docs:
- Blocks, `rescue` and `always`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_blocks.html
- `include_role` with `vars`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/include_role_module.html
- Variable precedence (why a task's `vars` beat the inventory but not `-e`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence
- `ansible_failed_task` and `ansible_failed_result` in a rescue: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_blocks.html#handling-errors-with-blocks

Traps:
- **Remember before you change.** `stat` on `/opt/acme-hello/current` gives `lnk_target`
  (`releases/1.1.0`); `| basename` is the version. Read it before the block, not in the rescue
  (by then current points at the broken release).
- **A rescue that succeeds swallows the failure**: the host counts as rescued and the play goes
  on with the next server. End the rescue with `ansible.builtin.fail` so the run exits non-zero
  and `max_fail_percentage: 0` stops it.
- **`always` runs after a failed rescue too**: that is where the server goes back into HAProxy,
  and `wait: true` makes sure it is really `UP` before the run ends.
- **Roll back through the role**, `include_role` with `vars: {acme_hello_version: <previous>}`: the
  link switch notifies the restart, `flush_handlers` runs it, and the health gate proves the old
  release healthy again. A task `vars:` beats the inventory's `acme_hello_version`. Don't
  override `app_version` there: `-e app_version=broken` is an extra var and beats everything.
- **Handlers and rescue:** the failed deploy already flushed its restart (the role does that
  before the health check), so nothing is left pending when the rescue starts.
- **First deploy on a fresh VM**: there is no previous release. Skip the rollback then, but still
  fail.
- **Don't reload HAProxy** in any of this: runtime state (drained servers) doesn't survive it.
