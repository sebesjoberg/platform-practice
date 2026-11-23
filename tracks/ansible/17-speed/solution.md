# an-17 solution

## Approach

Measure with `profile_tasks`, then remove waiting: one long-lived SSH connection per host
(`ControlPersist`), modules over that connection's stdin (pipelining), and facts from a local
cache instead of a gathering round per run. `linear` stays for `site.yml`: its baseline play uses
`run_once` + `delegate_to` (the runner's key), and the plays are short enough that `free` would
save seconds at the price of interleaved output.

## Code

`ansible/ansible.cfg`:

```ini
[defaults]
collections_path = ./collections
roles_path = ./roles
inventory = inventory/azure_rm.yml
interpreter_python = auto_silent
callback_result_format = yaml
forks = 20
gathering = smart
fact_caching = ansible.builtin.jsonfile
fact_caching_connection = ./.facts
fact_caching_timeout = 7200
callbacks_enabled = ansible.posix.profile_tasks

[inventory]
enable_plugins = azure.azcollection.azure_rm, ansible.builtin.host_list

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=600s -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
pipelining = True
```

`ansible/.gitignore`, added: `.facts/`.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
time ansible-playbook site.yml          # before: note the time and the slowest tasks
# change ansible.cfg and .gitignore
ansible-playbook site.yml               # fills the cache
time ansible-playbook site.yml          # after: changed=0, faster
ls .facts/                              # vm-{{PREFIX}}-jump vm-{{PREFIX}}-web-dev-1 vm-{{PREFIX}}-web-dev-2
git status --short                      # only ansible.cfg and .gitignore
grep -rn cacheable collections_src/ || echo "no cacheable facts"
```

On the lab's three VMs a second run typically goes from around two minutes to well under one;
the slowest tasks left are `apt` cache checks and the jump hop. Commit on a branch, pull request
(with both timings), merge: CI's runner jobs get faster too.

## Verify

`./lab.sh grade`: the settings in `ansible.cfg`, no cacheable facts, a second `site.yml` run with
`changed=0`, and a cache file per VM afterwards.
