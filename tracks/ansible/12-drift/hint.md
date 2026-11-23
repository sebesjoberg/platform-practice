# an-12 hints

Docs:
- Check mode and diff mode: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html
- `ansible_check_mode` and per-task `check_mode:`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html#enforcing-or-preventing-check-mode-on-tasks
- `ansible-playbook` options and return codes: https://docs.ansible.com/ansible/latest/cli/ansible-playbook.html

Traps:
- **`ansible-playbook --check` exits 0 even when tasks would change.** The exit code says
  whether the run worked, not whether the hosts match. Read the `PLAY RECAP`: drift is any
  `changed=` above 0. Failed and unreachable hosts are a different kind of red: the check
  didn't happen.
- **Modules without check mode are skipped** in check mode, and their registered result has no
  data. `ansible.builtin.uri` is one: the health wait in `acme_hello` then has no `.status`, and
  its `until:` expression fails the whole run. Either skip that task in check mode
  (`when: not ansible_check_mode`) or force it to run for real (`check_mode: false`, fine for a
  read-only GET, but then it waits 30 s for a restart that only happened in simulation).
- **`--diff` prints file contents.** Tasks that write secrets need `no_log: true` (an-07 and
  an-08 did that); the diff of everything else is what you want to see.
- **`set -o pipefail` with `| tee`**: keep the log for parsing and the output for the reader, and
  still get `ansible-playbook`'s exit code.
- **Colour codes** in the recap (CI forces colours sometimes) break naive parsing: strip
  `\033[...m` before you match `changed=`.
- **Remediate from the repo.** Fixing `nginx.conf` by hand on the VM would make the script green,
  but the next change by hand would go unnoticed the same way. A `site.yml` run puts back
  everything the roles own: the whole `nginx.conf` (an-06 made the role own it) and the running
  service.
- **Executable bit on Windows checkouts:** `git update-index --chmod=+x ansible/bin/drift-check.sh`.
