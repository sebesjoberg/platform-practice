# an-11 hints

Docs:
- `serial` and `max_fail_percentage`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html#setting-the-batch-size-with-serial
- Delegation (`delegate_to`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_delegation.html
- `community.general.haproxy` (drain, wait): https://docs.ansible.com/ansible/latest/collections/community/general/haproxy_module.html
- HAProxy's Runtime API (`set server ... state`, `show stat`): https://docs.haproxy.org/2.8/management.html#9.3

Traps:
- **`community.general` is already pinned** (an-01): its `haproxy` module speaks the Runtime API.
  `state: disabled` with `drain: true` waits until the server has no connections left and is in
  `MAINT`; `state: enabled` with `wait: true` waits until HAProxy reports it `UP`. Without the
  wait, the next server can leave the pool before this one is back, and for a few seconds
  nothing serves.
- **Delegated tasks run with the play's `become`** on the jump host. The socket is mode 660,
  group `haproxy` (an-10): root gets in, `azureuser` doesn't.
- **`max_fail_percentage: 0`** with `serial: 1`: one failed server is 100 % of its batch, so the
  play ends before the next batch. Leave the failed server drained; it gets attention in an-18.
- **A HAProxy reload forgets runtime state** (drained or disabled servers come back enabled).
  `rolling.yml` touches only the web servers and HAProxy's socket, never its config.
- **The health gate is in the role** (an-09), after `meta: flush_handlers`: when the role is
  done, the new release answers. Put the server back in `post_tasks`, which run after the roles.
- **`-e app_version=1.0.0`** beats the inventory (extra vars win over everything). That is why it
  is only for one-offs: the next plain run rolls the inventory's `1.1.0` again.
- **Test it like the grader does**: a curl loop on the jump host (`ssh` to it, or
  `ansible role_jump -m shell -a ...` in a second terminal) while the play runs. A single `502`
  or `503` means a server took requests while it restarted, or none was in the pool.
