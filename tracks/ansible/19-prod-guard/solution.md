# an-19 solution

## Approach

The Azure inventory includes the prod resource group (prod VMs would appear in `env_prod` by
their tag), and a small static file declares `env_prod` so the group exists while it's empty: a
fixture-free, honest inventory. One guard playbook, imported first by everything that changes
the fleet, refuses prod hosts before any connection unless `-e confirm_prod=true`. Dev runs say
`--limit env_dev:env_hub`; the only `confirm_prod` is in CI's approved prod job.

## Code

`inventory/azure_rm.yml`: `rg-{{PREFIX}}-prod` added to `include_vm_resource_groups`.

`inventory/groups.yml`:

```yaml
---
all:
  children:
    env_prod:
```

`ansible.cfg`:

```ini
inventory = inventory/azure_rm.yml, inventory/groups.yml
...
[inventory]
enable_plugins = azure.azcollection.azure_rm, ansible.builtin.yaml, ansible.builtin.host_list
```

`inventory/group_vars/env_prod.yml`:

```yaml
---
acme_env: prod
acme_kv_url: https://kv-{{PREFIX}}-prod-{{SUFFIX}}.vault.azure.net
acme_log_level: info
```

`ansible/guard.yml`:

```yaml
---
- name: Refuse prod hosts without -e confirm_prod=true
  hosts: all
  gather_facts: false
  any_errors_fatal: true
  tasks:
    - name: A run that includes prod hosts must say -e confirm_prod=true
      ansible.builtin.assert:
        that: confirm_prod | default(false) | bool
        fail_msg: >-
          {{ inventory_hostname }} is in env_prod: runs against prod need -e confirm_prod=true (CI's
          approved prod job). For dev only, add --limit env_dev:env_hub.
        quiet: true
      when: "'env_prod' in group_names"
```

First in `site.yml` and `deploy.yml`:

```yaml
- name: Guard against accidental prod runs
  ansible.builtin.import_playbook: guard.yml
```

`inventory/group_vars/role_jump.yml`:

```yaml
haproxy_backends: >-
  {{ dict(groups['role_web'] | intersect(groups['env_dev'])
  | zip(groups['role_web'] | intersect(groups['env_dev']) | map('extract', hostvars, ['private_ipv4_addresses', 0]))) }}
```

`.github/workflows/ansible.yml`: `env` options `[dev, prod]`; `--limit env_dev:env_hub` in
`check`, `apply` and the `drift-check.sh` call; and:

```yaml
  apply-prod:
    if: github.event_name == 'workflow_dispatch' && inputs.env == 'prod' && inputs.task == 'apply' && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: [self-hosted, acme-jump]
    environment: prod
    env:  # as in apply
    steps:
      # checkout, ci-toolchain.sh
      - id: hosts
        working-directory: ansible
        run: |
          n="$(ansible env_prod --list-hosts -e @ci/runner.yml 2>/dev/null | sed -nE 's/^[[:space:]]*hosts \(([0-9]+)\):.*/\1/p')"
          echo "count=${n:-0}" >>"$GITHUB_OUTPUT"
      - if: steps.hosts.outputs.count == '0'
        run: echo "::notice::env_prod has no hosts yet; nothing to apply"
      - if: steps.hosts.outputs.count != '0'
        working-directory: ansible
        run: ansible-playbook site.yml --limit env_prod -e confirm_prod=true -e @ci/runner.yml -e acme_kv_auth_source=msi
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-inventory --graph | grep -A1 env_prod          # @env_prod: (empty)
cat > /tmp/fixture.yml <<'EOF'
all:
  vars: {ansible_ssh_timeout: 3}
  children:
    role_web: {hosts: {fake-web-prod-1: {ansible_host: 192.0.2.10}}}
    env_prod: {hosts: {fake-web-prod-1: }}
EOF
ansible-playbook site.yml -i /tmp/fixture.yml --limit env_prod; echo "exit $?"
#   TASK [A run that includes prod hosts must say -e confirm_prod=true]
#   fatal: [fake-web-prod-1]: FAILED! => ... is in env_prod: runs against prod need -e confirm_prod=true
ansible-playbook site.yml -i /tmp/fixture.yml --limit env_prod -e confirm_prod=true   # past the guard: UNREACHABLE
ansible-lint && ansible-playbook site.yml --limit env_dev:env_hub                   # changed=0
```

Commit on a branch, pull request, merge. `gh workflow run ansible.yml -f env=prod` waits for your
approval, then reports that `env_prod` has no hosts.

## Verify

`./lab.sh grade` runs the guard against its own fixture inventory (prod refused before any
connection, `confirm_prod=true` and dev-only runs let through) and checks the empty `env_prod` in
the real inventory.
