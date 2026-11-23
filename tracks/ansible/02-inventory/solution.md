# an-02 solution

## Approach

The plugin queries Azure for the VMs in the two resource groups, names them after the VM and
groups them by tag. Connection settings live in `inventory/group_vars/`, which Ansible loads for
any command that uses this inventory (ad-hoc too). The web hosts get a ProxyCommand templated
from the jump host's `public_ipv4_address`, a host variable the plugin sets.

## Code

`ansible/inventory/azure_rm.yml`:

```yaml
---
plugin: azure.azcollection.azure_rm
auth_source: cli
include_vm_resource_groups:
  - rg-{{PREFIX}}-shared
  - rg-{{PREFIX}}-dev
hostnames:
  - name
keyed_groups:
  - prefix: role
    key: tags.role | default('untagged')
  - prefix: env
    key: tags.env | default('untagged')
```

`ansible/inventory/group_vars/all.yml`:

```yaml
---
ansible_user: azureuser
ansible_ssh_private_key_file: ~/.ssh/{{PREFIX}}_lab
```

`ansible/inventory/group_vars/role_web.yml`:

```yaml
---
jump_host_ip: "{{ hostvars[groups['role_jump'] | first]['public_ipv4_address'] | first }}"
ansible_ssh_common_args: >-
  -o ProxyCommand="ssh -W %h:%p -q
  -i {{ ansible_ssh_private_key_file }} -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  {{ ansible_user }}@{{ jump_host_ip }}"
```

Added to `ansible/ansible.cfg`:

```ini
[defaults]
inventory = inventory/azure_rm.yml

[inventory]
enable_plugins = azure.azcollection.azure_rm, ansible.builtin.host_list

[ssh_connection]
# Lab VMs get new host keys on every pause/resume: keys are not recorded.
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
az account show --query name -o tsv          # the lab subscription
ansible-inventory --graph
#  @all:
#    |--@ungrouped:
#    |--@role_jump:
#    |  |--vm-{{PREFIX}}-jump
#    |--@env_hub: ...
#    |--@role_web:
#    |  |--vm-{{PREFIX}}-web-dev-1
#    |  |--vm-{{PREFIX}}-web-dev-2
#    |--@env_dev: ...
ansible-inventory --host vm-{{PREFIX}}-jump | jq '.public_ipv4_address, .tags'
ansible all -m ansible.builtin.ping
ansible vm-{{PREFIX}}-web-dev-1 -m ansible.builtin.ping -vvv | grep -m1 ProxyCommand   # the resolved jump IP
```

Commit on a branch and merge it with a pull request.

## Verify

`./lab.sh grade`. Nothing new in Azure; the inventory only reads (`Reader` is enough).
