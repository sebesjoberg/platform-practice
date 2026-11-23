# an-06 solution

## Approach

The role owns all of `/etc/nginx/nginx.conf`, server block included. That makes `validate:` mean
something: the temp file nginx checks is the complete configuration it will load, and a broken
template is refused before it touches `/etc/nginx`. The page is a template with the hostname fact
and `nginx_site_env`, which the inventory sets from `env_dev.yml`.

## Code

Layout:

```text
ansible/
  site.yml                                  # + play "Web servers": hosts role_web, role nginx
  inventory/group_vars/env_dev.yml          # acme_env: dev
  inventory/group_vars/role_web.yml         # + nginx_site_env: "{{ acme_env }}"
  roles/nginx/
    defaults/main.yml                       # nginx_site_env, nginx_root, nginx_worker_connections
    meta/main.yml  meta/argument_specs.yml
    tasks/main.yml  handlers/main.yml
    templates/nginx.conf.j2  templates/index.html.j2
    molecule/default/                       # molecule.yml, Dockerfile.j2 (copied from base), converge.yml, verify.yml
```

`roles/nginx/tasks/main.yml` (the core):

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
    cache_valid_time: 3600
    lock_timeout: 600

- name: Write the start page
  ansible.builtin.template:
    src: index.html.j2
    dest: "{{ nginx_root }}/index.html"
    owner: root
    group: root
    mode: "0644"

- name: Write the nginx configuration
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: "0644"
    validate: /usr/sbin/nginx -t -q -c %s
  notify: Reload nginx

- name: Remove the distribution's default site
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent

- name: Keep nginx running and enabled
  ansible.builtin.systemd_service:
    name: nginx
    state: started
    enabled: true
```

(plus a `file` task for the document root before the page). `templates/nginx.conf.j2`, the part
that matters:

```nginx
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections {{ nginx_worker_connections }}; }
http {
    server_tokens off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server {
        listen 80 default_server;
        server_name _;
        root {{ nginx_root }};
        location / { try_files $uri $uri/ =404; }
    }
}
```

`templates/index.html.j2` shows `{{ ansible_facts['hostname'] }}` and
`env: {{ nginx_site_env }}`. `handlers/main.yml`: `Reload nginx`, `systemd_service` with
`state: reloaded`.

`site.yml`, the new play:

```yaml
- name: Web servers
  hosts: role_web
  become: true
  roles:
    - role: nginx
```

Molecule: the base scenario with the platform renamed `nginx-noble`; `converge.yml` applies
`nginx` with `nginx_site_env: molecule`; `verify.yml` runs `nginx -t`, checks the unit is active
and enabled, fetches `http://127.0.0.1/` with `uri` and asserts the hostname and `env: molecule`,
and that `sites-enabled/default` is gone.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd roles/nginx && molecule test)
ansible-lint
ansible-playbook site.yml
ansible role_web -b -m ansible.builtin.shell -a 'curl -s localhost'
# prove the gate: break the template (drop a ;), run, read the validate error, revert
ansible-playbook site.yml      # changed=0
```

From the jump host: `curl -s http://<web private IP>/`. Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade` (it runs `molecule test` for nginx and `site.yml` once more).
