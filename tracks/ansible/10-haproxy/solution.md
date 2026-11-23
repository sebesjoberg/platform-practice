# an-10 solution

## Approach

A generic `haproxy` role that takes a dict of backend servers (name → address) and the inventory
that builds it from `groups['role_web']` and each web host's `private_ipv4_addresses`. The role
templates the whole `haproxy.cfg` (validated with `haproxy -c`), keeps the Runtime API socket at
level admin, and reloads through a handler. A third play in `site.yml` applies it to the jump
host after the web servers.

## Code

`ansible/inventory/group_vars/role_jump.yml`:

```yaml
---
haproxy_backends: >-
  {{ dict(groups['role_web']
  | zip(groups['role_web'] | map('extract', hostvars, ['private_ipv4_addresses', 0]))) }}
```

`roles/haproxy/templates/haproxy.cfg.j2`:

```text
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket {{ haproxy_admin_socket }} mode 660 group {{ haproxy_admin_group }} level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option forwardfor
    option redispatch
    retries 2
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend http
    bind {{ haproxy_bind }}:{{ haproxy_frontend_port }}
    default_backend {{ haproxy_backend_name }}

backend {{ haproxy_backend_name }}
    balance roundrobin
    option httpchk GET {{ haproxy_health_path }}
    http-check expect status 200
    default-server inter 2s fall 2 rise 2
{% for name, address in haproxy_backends | dictsort %}
    server {{ name }} {{ address }}:{{ haproxy_backend_port }} check
{% endfor %}
```

`roles/haproxy/tasks/main.yml`:

```yaml
- name: Install HAProxy, and socat to talk to its Runtime API by hand
  ansible.builtin.apt:
    name: [haproxy, socat]
    state: present
    update_cache: true
    cache_valid_time: 3600
    lock_timeout: 600

- name: Write the HAProxy configuration
  ansible.builtin.template:
    src: haproxy.cfg.j2
    dest: /etc/haproxy/haproxy.cfg
    owner: root
    group: root
    mode: "0644"
    validate: /usr/sbin/haproxy -c -q -f %s
  notify: Reload haproxy

# + a drop-in that resets BindReadOnlyPaths, when: not haproxy_mount_namespace (Molecule only)

- name: Keep HAProxy running and enabled
  ansible.builtin.systemd_service:
    name: haproxy
    state: started
    enabled: true
    daemon_reload: "{{ not haproxy_mount_namespace }}"
```

Defaults: `haproxy_bind: "*"`, `haproxy_frontend_port: 80`, `haproxy_backend_name: web`,
`haproxy_backend_port: 80`, `haproxy_health_path: /health`,
`haproxy_admin_socket: /run/haproxy/admin.sock`, `haproxy_admin_group: haproxy`,
`haproxy_mount_namespace: true`.
Handler `Reload haproxy`: `systemd_service` `state: reloaded`.

`site.yml`, the third play:

```yaml
- name: Load balancer
  hosts: role_jump
  become: true
  roles:
    - role: haproxy
```

Molecule: `prepare.yml` writes `/srv/web-{a,b}/index.html` and `health` and starts
`systemd-run --unit fake-web-a /usr/bin/python3 -m http.server 8081 --bind 127.0.0.2 ...` (and
`web-b` on `127.0.0.3`); `converge.yml` passes those two as `haproxy_backends` with
`haproxy_backend_port: 8081` and `haproxy_mount_namespace: false`; `verify.yml` checks
`haproxy -c`, the unit, the socket (`issock`, group `haproxy`, `0660`), `show servers state web` through socat,
and that ten `uri` requests to `http://127.0.0.1/` reached both.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd roles/haproxy && molecule test)
ansible-lint && ansible-playbook site.yml
ansible role_jump -m ansible.builtin.shell -a 'for i in $(seq 10); do curl -s localhost; done'
ansible role_jump -b -m ansible.builtin.shell -a 'echo "show servers state web" | socat stdio /run/haproxy/admin.sock'
ansible-playbook site.yml      # changed=0
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade`. Nothing in Azure changes (no NSG rule: port 80 stays closed from outside).
