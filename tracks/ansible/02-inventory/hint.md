# an-02 hints

Docs:
- The `azure_rm` inventory plugin (options, host variables such as `public_ipv4_address`): https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_rm_inventory.html
- Constructed features (`keyed_groups`, `compose`, `hostnames`): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/constructed_inventory.html
- `group_vars` next to an inventory source: https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables
- Connection variables (`ansible_ssh_common_args`, `ansible_ssh_private_key_file`): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ssh_connection.html

Traps:
- **The file name matters.** The plugin only accepts a config file ending in `azure_rm.yml` or
  `azure_rm.yaml`.
- **Default hostnames are hashed** (`vm-{{PREFIX}}-jump_1a2b`). `hostnames: [name]` (or
  `plain_host_names: true`) gives the VM names.
- **`keyed_groups` with `key: tags`** makes `tag_role_web`; you want `prefix: role` with
  `key: tags.role` (and a `default(...)` for untagged VMs, or the group key errors out).
- **Inventory compose can't see other hosts.** `compose` and `hostvar_expressions` are evaluated
  per host, so the jump host's IP isn't available there. Put the ProxyCommand in
  `inventory/group_vars/role_web.yml` and template it from
  `hostvars[groups['role_jump'] | first]`: group variables are templated lazily, when Ansible
  connects, so the value always matches the current inventory.
- **`ProxyCommand` doesn't inherit your options.** The inner `ssh -W %h:%p ...` needs its own
  `-i ~/.ssh/{{PREFIX}}_lab` and the same host-key options as the outer connection. Plain
  `ProxyJump` (`-J`) ignores the outer `-i` for the jump hop.
- **Host keys.** After a resume the old keys in `~/.ssh/known_hosts` belong to other machines:
  SSH then refuses (strict checking) or connects without forwarding, and `-W` is forwarding. For
  this disposable lab, `UserKnownHostsFile=/dev/null` + `StrictHostKeyChecking=no` on both hops is
  defensible; say so in a comment. A long-lived fleet pins host keys or uses SSH host certificates.
- **`ssh_args` replaces Ansible's defaults**, including `ControlMaster`/`ControlPersist`. Put them
  back when you set it, or every task opens a new SSH connection (twice, for the web VMs).
- **Add `-o IdentitiesOnly=yes` to `ssh_args`** (and to the inner ProxyCommand ssh). Without it,
  ssh offers every key in your ssh-agent before the lab key; once an-03 sets `MaxAuthTries 3`, an
  agent with three or more keys gets every VM to reject Ansible after the first run.
- **The jump host's IP must not be in any file**, not even a `jump_host_ip: 20.x.x.x` in another
  group_vars file: the grader looks for the real IP under `ansible/`.
- **Which subscription?** The plugin uses the `az` CLI's current subscription:
  `az account show` must print the lab subscription.
- **An empty inventory is not an error.** `ansible all -m ping` with no hosts exits 0 with a
  warning. Read the output (or `ansible all --list-hosts`).
- **Paused lab:** stopped or missing VMs are filtered out by the plugin's default filters, and
  `groups['role_jump']` is then undefined. `./lab.sh resume` first.
