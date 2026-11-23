# an-07 solution

## Approach

Split "where does the value come from" from "what does the server need". The role `app_env`
writes whatever dict it gets into `/etc/acme/app.env`, with `no_log`; the inventory fills that
dict with Key Vault lookups. The vault URL is per environment (`env_dev.yml`), the auth source a
fleet-wide variable that CI overrides with `-e`. Molecule passes a stub dict.

## Code

`ansible/inventory/group_vars/all.yml`, added:

```yaml
# cli = your az login here; CI on the jump host (an-16) runs with -e acme_kv_auth_source=msi.
acme_kv_auth_source: cli
```

`ansible/inventory/group_vars/env_dev.yml`, added:

```yaml
acme_kv_url: https://kv-{{PREFIX}}-dev-{{SUFFIX}}.vault.azure.net
```

`ansible/inventory/group_vars/role_web.yml`, added:

```yaml
app_env_vars:
  APP_GREETING: >-
    {{ lookup('azure.azcollection.azure_keyvault_secret', 'app-greeting',
    vault_url=acme_kv_url, auth_source=acme_kv_auth_source,
    use_msi=(acme_kv_auth_source == 'msi')) }}
```

`ansible/roles/app_env/tasks/main.yml`:

```yaml
---
- name: Create the application group
  ansible.builtin.group:
    name: "{{ app_env_group }}"
    system: true

- name: Create the configuration directory
  ansible.builtin.file:
    path: "{{ app_env_path | dirname }}"
    state: directory
    owner: root
    group: "{{ app_env_group }}"
    mode: "0750"

- name: Write the environment file
  ansible.builtin.template:
    src: app.env.j2
    dest: "{{ app_env_path }}"
    owner: root
    group: "{{ app_env_group }}"
    mode: "0640"
  no_log: true
```

`templates/app.env.j2`:

```jinja
# {{ ansible_managed }} (role app_env)
{% for name, value in app_env_vars | dictsort %}
{{ name }}={{ value }}
{% endfor %}
```

`defaults/main.yml`: `app_env_path: /etc/acme/app.env`, `app_env_group: acme`.
`meta/argument_specs.yml` makes `app_env_vars` a required dict with `no_log: true`.
`site.yml`'s web play: `roles: [app_env, nginx]`.

Molecule: copy the nginx scenario to `roles/app_env/molecule/default`; `converge.yml` sets
`app_env_vars: {APP_GREETING: molecule-stub-not-a-secret, APP_MODE: test}`; `verify.yml` asserts
owner, group and mode with `stat` and the lines with `slurp`.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd roles/app_env && molecule test)
ansible-playbook site.yml --check --diff -v | grep -c "$(az keyvault secret show \
  --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n app-greeting --query value -o tsv)"   # 0
ansible-playbook site.yml
ansible role_web -b -m ansible.builtin.command -a 'stat -c "%a %U %G" /etc/acme/app.env'
ansible-lint && ansible-playbook site.yml      # changed=0
```

Commit on a branch, pull request, merge. Before you push:
`git grep -F "<the value>"` and `git log -S"<the value>" --all` find nothing.

## Verify

`./lab.sh grade`. The secret stays in the vault; nothing to clean up. `./lab.sh resume` stores a
new secret in the new, empty vault and re-runs `site.yml`; if it fails there, run
`tracks/ansible/lib/keyvault-prereqs.sh` from the lab directory, then `site.yml`.
