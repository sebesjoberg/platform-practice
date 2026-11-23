# an-09 solution

## Approach

Releases as artifacts: each version is a directory under the role's `files/releases/`, copied to
`/opt/acme-hello/releases/<version>/` and activated by pointing `/opt/acme-hello/current` at it.
The unit runs `current/acme_hello.py` as the system user `acme-hello`, which needs no access to
`app.env` (systemd reads `EnvironmentFile=` as root before it drops privileges), with hardening
that splits into a part that works everywhere and a mount-namespace part behind
`acme_hello_sandbox` (off in Molecule only). Changes notify one restart handler, flushed before a
`uri` loop that waits for `ok <version>`: the version the running code reports, not the one in
the config. nginx gets an optional `nginx_proxy_pass`.

## Code

`ansible/inventory/group_vars/role_web.yml`, added:

```yaml
app_version: "1.0.0"
acme_hello_version: "{{ app_version }}"
acme_hello_env: "{{ acme_env }}"
nginx_proxy_pass: http://127.0.0.1:8080
```

`roles/acme_hello/tasks/main.yml` (the user/group tasks shortened):

```yaml
- name: Check that the release exists in the role
  ansible.builtin.assert:
    that: (role_path ~ '/files/releases/' ~ acme_hello_version ~ '/acme_hello.py') is file
    quiet: true

# group acme-hello and user acme-hello: system, nologin, no home

- name: Create the release directory
  ansible.builtin.file:
    path: "{{ acme_hello_home }}/releases/{{ acme_hello_version }}"
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Install the release
  ansible.builtin.copy:
    src: "releases/{{ acme_hello_version }}/acme_hello.py"
    dest: "{{ acme_hello_home }}/releases/{{ acme_hello_version }}/acme_hello.py"
    owner: root
    group: root
    mode: "0755"
  notify: Restart acme-hello

- name: Point current at the release
  ansible.builtin.file:
    src: "releases/{{ acme_hello_version }}"
    dest: "{{ acme_hello_home }}/current"
    state: link
  notify: Restart acme-hello

- name: Install the systemd unit
  ansible.builtin.template:
    src: acme-hello.service.j2
    dest: /etc/systemd/system/acme-hello.service
    owner: root
    group: root
    mode: "0644"
  notify: Restart acme-hello

- name: Keep acme-hello enabled and running
  ansible.builtin.systemd_service:
    name: acme-hello
    state: started
    enabled: true

- name: Restart now if the release or the unit changed
  ansible.builtin.meta: flush_handlers

- name: Wait until the app reports healthy with this release
  ansible.builtin.uri:
    url: "http://127.0.0.1:{{ acme_hello_port }}/health"
    return_content: true
  register: acme_hello_health
  until: acme_hello_health.status == 200 and (acme_hello_health.content | trim) == 'ok ' ~ acme_hello_version
  retries: "{{ acme_hello_health_retries }}"
  delay: 2
  changed_when: false
```

Handler: `Restart acme-hello`, `systemd_service` with `state: restarted` and `daemon_reload: true`.

`templates/acme-hello.service.j2`:

```ini
[Service]
User={{ acme_hello_user }}
Group={{ acme_hello_user }}
EnvironmentFile=-{{ acme_hello_env_file }}
Environment=APP_ENV={{ acme_hello_env }} APP_PORT={{ acme_hello_port }}
ExecStart=/usr/bin/python3 {{ acme_hello_home }}/current/acme_hello.py
Restart=on-failure
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressDeny=any
IPAddressAllow=localhost
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
ProtectClock=yes
ProtectHostname=yes
UMask=0077
{% if acme_hello_sandbox %}
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectProc=invisible
ProcSubset=pid
{% endif %}
```

(plus `[Unit]` with `After=network.target` and `[Install]` with `WantedBy=multi-user.target`).
nginx: `nginx_proxy_pass: ""` in defaults and argument specs, and in `nginx.conf.j2`'s
`location /`: `proxy_pass {{ nginx_proxy_pass }};` with `Host`, `X-Forwarded-For` and
`X-Forwarded-Proto` headers when it is set, `try_files` otherwise. `site.yml`'s web play:
`roles: [app_env, acme_hello, nginx]`.

Molecule: the nginx scenario renamed; `converge.yml` sets `acme_hello_env: molecule` and
`acme_hello_sandbox: false`; `verify.yml` asserts the unit is active, enabled and runs as
`acme-hello`, `/health` is `ok 1.0.0`, the page names release, host and `(molecule)`, `current`
links to `releases/1.0.0`, and `systemd-analyze security --threshold=49` passes.

## Commands

```bash
cp -R ~/.platform-lab/starter/an-09/releases "$LIVE_DIR/ansible/roles/acme_hello/files/"
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd roles/acme_hello && molecule test)
ansible-lint && ansible-playbook site.yml
ansible role_web -b -m ansible.builtin.shell -a 'curl -s localhost/; curl -s localhost/health; systemd-analyze security acme-hello.service | tail -1'
ansible-playbook site.yml -e app_version=broken     # one-off: fails at "Wait until the app reports healthy"
ansible-playbook site.yml                           # the inventory's 1.0.0 again
ansible-playbook site.yml                           # changed=0
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade`. An aborted broken deploy leaves `current` on `broken`: the next normal run
switches it back. Releases accumulate in `/opt/acme-hello/releases`; pruning old ones is a later
refinement.
