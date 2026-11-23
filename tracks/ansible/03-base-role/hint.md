# an-03 hints

Docs:
- `template` / `copy` with `validate`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html
- Handlers (and `systemd_service` `state: reloaded`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html
- `ansible.posix.authorized_key` (`exclusive`): https://docs.ansible.com/ansible/latest/collections/ansible/posix/authorized_key_module.html
- Role argument validation (`meta/argument_specs.yml`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#role-argument-validation

Traps:
- **First value wins in sshd.** Ubuntu's `sshd_config` includes `sshd_config.d/*.conf` at the very
  top, in lexical order, and for most keywords sshd keeps the first value it reads. cloud-init
  already wrote `50-cloud-init.conf`. Name your drop-in so it sorts first (`00-...`), and check the
  effective result with `sudo sshd -T`, not by reading files.
- **`sshd -t -f %s` validates the drop-in on its own**, as a complete config. That works (sshd
  falls back to the default host keys) but needs root: `become: true`.
- **Don't lock yourself out.** Keep `azureuser`'s key login working (it's how Ansible connects),
  and don't set `AllowTcpForwarding no` on the jump host: your SSH to the web VMs is forwarded
  through it. Test with the handler's reload (open sessions survive), and keep a second session open.
- **The service is `ssh`**, not `sshd`, on Ubuntu (24.04 starts it through `ssh.socket`).
- **Idempotence killers:** `apt` with `update_cache: true` but no `cache_valid_time` (changed on
  every run); `command`/`shell` without `changed_when`; `user` with a plaintext `password`;
  templates with a timestamp in them.
- **`authorized_key` with a list:** `key:` takes one string; join the list with newlines and set
  `exclusive: true`, or a second run (or a removed key) leaves stale keys behind.
- **The ops key in the inventory:** `lookup('ansible.builtin.file', '~/.ssh/{{PREFIX}}_lab.pub')`
  in `inventory/group_vars/all.yml` reads the public key on the control node; the role stays
  generic.
- **chrony on Azure** already syncs from the host clock (a PTP refclock in the image's
  `chrony.conf`). Add sources as a drop-in (`/etc/chrony/sources.d/*.sources`) instead of
  replacing `chrony.conf`.
- **The grader runs `site.yml` with a 5-minute limit.** Three small VMs take one to two minutes;
  much more means something reconnects on every task (see an-02's `ControlPersist`).
