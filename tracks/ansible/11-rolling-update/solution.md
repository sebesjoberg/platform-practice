# an-11 solution

## Approach

One play, `serial: 1`, wrapped around the existing role. `pre_tasks` drain the server in HAProxy
(delegated to the jump host found through `groups['role_jump']`), the role deploys and waits for
`/health`, `post_tasks` put the server back and wait for HAProxy's own `UP`.
`max_fail_percentage: 0` ends the run at the first unhealthy server, so the other one keeps
serving. The release itself is one line in the inventory.

## Code

`ansible/inventory/group_vars/role_web.yml`:

```yaml
app_version: "1.1.0"
```

`ansible/rolling.yml`:

```yaml
---
- name: Roll the app out over the web servers
  hosts: role_web
  become: true
  serial: 1
  max_fail_percentage: 0
  vars:
    rolling_lb_host: "{{ groups['role_jump'] | first }}"
    rolling_lb_socket: /run/haproxy/admin.sock
    rolling_lb_backend: web
  pre_tasks:
    - name: Drain this server in HAProxy and wait until its connections are gone
      community.general.haproxy:
        state: disabled
        drain: true
        wait: true
        wait_interval: 2
        wait_retries: 30
        host: "{{ inventory_hostname }}"
        backend: "{{ rolling_lb_backend }}"
        socket: "{{ rolling_lb_socket }}"
      delegate_to: "{{ rolling_lb_host }}"

  roles:
    - role: acme_hello

  post_tasks:
    - name: Put this server back into the pool and wait until HAProxy reports it UP
      community.general.haproxy:
        state: enabled
        wait: true
        wait_interval: 2
        wait_retries: 30
        host: "{{ inventory_hostname }}"
        backend: "{{ rolling_lb_backend }}"
        socket: "{{ rolling_lb_socket }}"
      delegate_to: "{{ rolling_lb_host }}"
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-lint

# second terminal: the load test the grader runs
ansible role_jump -m ansible.builtin.shell -a \
  'for i in $(seq 600); do curl -s -o /dev/null -w "%{http_code}\n" localhost; sleep 0.2; done | sort | uniq -c'

ansible-playbook rolling.yml -e app_version=1.0.0   # one-off: both servers back to 1.0.0, one by one
ansible-playbook rolling.yml                        # the inventory's 1.1.0
ansible role_web -m ansible.builtin.command -a 'curl -s localhost/health'
ansible role_jump -b -m ansible.builtin.shell -a 'echo "show servers state web" | socat stdio /run/haproxy/admin.sock'
ansible-playbook site.yml                           # changed=0: site.yml agrees with rolling.yml
```

The load test prints only `200` lines. Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade`. It starts its own request loop on the jump host (it stops by itself), runs both
rolling runs and counts the non-200 answers. Nothing in Azure changes.
