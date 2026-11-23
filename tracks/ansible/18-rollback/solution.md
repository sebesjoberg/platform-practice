# an-18 solution

## Approach

an-11's play with the deploy wrapped in `block`/`rescue`/`always`. The previous release is read
from the `current` symlink before anything changes; the rescue deploys it again through the same
role (so the restart and the health gate apply to the rollback too) and then fails the run; the
`always` returns the server to HAProxy. `rolling.yml` becomes an import of `deploy.yml`.

## Code

`ansible/deploy.yml`:

```yaml
---
- name: Deploy the app with automatic rollback
  hosts: role_web
  become: true
  serial: 1
  max_fail_percentage: 0
  vars:
    deploy_lb_host: "{{ groups['role_jump'] | first }}"
    deploy_lb_socket: /run/haproxy/admin.sock
    deploy_lb_backend: web
  tasks:
    - name: Find the release that runs now
      ansible.builtin.stat:
        path: /opt/acme-hello/current
      register: deploy_current

    - name: Remember it
      ansible.builtin.set_fact:
        deploy_previous: "{{ (deploy_current.stat.lnk_target | basename) if (deploy_current.stat.islnk | default(false)) else '' }}"

    - name: Deploy, and roll back if the release isn't healthy
      block:
        - name: Drain this server in HAProxy and wait until its connections are gone
          community.general.haproxy:
            state: disabled
            drain: true
            wait: true
            wait_interval: 2
            wait_retries: 30
            host: "{{ inventory_hostname }}"
            backend: "{{ deploy_lb_backend }}"
            socket: "{{ deploy_lb_socket }}"
          delegate_to: "{{ deploy_lb_host }}"

        - name: Deploy the release (the role waits for /health = ok <version>)
          ansible.builtin.include_role:
            name: acme.platform.acme_hello

      rescue:
        - name: Roll back to the release that ran before
          ansible.builtin.include_role:
            name: acme.platform.acme_hello
          vars:
            acme_hello_version: "{{ deploy_previous }}"
          when: deploy_previous | length > 0 and deploy_previous != acme_hello_version

        - name: Fail the deploy (the next server stays untouched)
          ansible.builtin.fail:
            msg: >-
              Release {{ acme_hello_version }} failed on {{ inventory_hostname }}
              ({{ ansible_failed_task.name | default('a task') }}); rolled back to
              {{ deploy_previous if deploy_previous | length > 0 else 'nothing (no release ran before)' }}.

      always:
        - name: Put this server back into the pool and wait until HAProxy reports it UP
          community.general.haproxy:
            state: enabled
            wait: true
            wait_interval: 2
            wait_retries: 30
            host: "{{ inventory_hostname }}"
            backend: "{{ deploy_lb_backend }}"
            socket: "{{ deploy_lb_socket }}"
          delegate_to: "{{ deploy_lb_host }}"
```

`ansible/rolling.yml`:

```yaml
---
- name: Rolling update with automatic rollback
  ansible.builtin.import_playbook: deploy.yml
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-lint
ansible-playbook deploy.yml -e app_version=broken; echo "exit $?"
#   TASK [acme.platform.acme_hello : Wait until the app reports healthy with this release]
#   FAILED - RETRYING ... fatal: [vm-{{PREFIX}}-web-dev-1]
#   TASK [Roll back to the release that ran before] ... ok: health ok 1.1.0
#   TASK [Fail the deploy ...] fatal: Release broken failed ...; rolled back to 1.1.0.
#   TASK [Put this server back into the pool ...] changed
#   NO MORE HOSTS LEFT; exit 2
ansible role_web -m ansible.builtin.command -a 'curl -s localhost/health'   # ok 1.1.0 twice
ansible role_jump -b -m ansible.builtin.shell -a 'echo "show servers state web" | socat stdio /run/haproxy/admin.sock'
ansible-playbook site.yml                                                  # changed=0
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade` runs `deploy.yml -e app_version=broken` itself (it must fail), then checks
`/health` on both VMs, HAProxy's view of both servers, and a clean `site.yml` run. The broken
release stays on disk in `/opt/acme-hello/releases/broken`; nothing runs it.
