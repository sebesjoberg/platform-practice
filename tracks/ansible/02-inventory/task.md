---
id: an-02
title: Dynamic inventory through the jump host
target_minutes: 20
requires: [tf-25, an-01]
---
# an-02 Dynamic inventory through the jump host

A static `hosts.ini` lasts until the first `./lab.sh pause`: resume gives the jump host a new
public IP, and the web VMs may come back with other private ones. The inventory has to come from
Azure itself, grouped by the tags Terraform puts on every VM, and the two web servers, which have
no public IP, must be reachable through the jump host without anyone pasting an address into a
file.

## Deliverables

- [ ] `ansible/inventory/azure_rm.yml` with the `azure.azcollection.azure_rm` plugin:
  - [ ] `auth_source: cli` (your `az login`; CI will override it later, the file stays)
  - [ ] only the VMs of `rg-{{PREFIX}}-shared` and `rg-{{PREFIX}}-dev`
  - [ ] inventory hostnames are the VM names: `vm-{{PREFIX}}-jump`, `vm-{{PREFIX}}-web-dev-1`,
        `vm-{{PREFIX}}-web-dev-2`
  - [ ] `keyed_groups` on the tags `role` and `env`, giving exactly the groups `role_jump`,
        `role_web`, `env_hub` and `env_dev`
- [ ] `ansible/ansible.cfg` uses that inventory by default, and enables only the inventory
      plugins you need.
- [ ] Every host: user `azureuser`, key `~/.ssh/{{PREFIX}}_lab` (group variables next to the
      inventory, so ad-hoc `ansible` sees them too).
- [ ] The web hosts connect through the jump host: `ansible_ssh_common_args` with a
      ProxyCommand (or ProxyJump) to `azureuser@<jump public IP>`, where the IP is **looked up
      from the inventory at run time** (the jump host's host variables), never written down.
- [ ] Host keys: the VMs are rebuilt with new keys by every pause/resume. Decide how SSH treats
      that (and write the reason next to the setting).

## Done when

From `ansible/`, `ansible-inventory --graph` shows `@role_web` and `@env_dev` with both web VMs
and `@role_jump` with the jump VM, `ansible all -m ping` answers `pong` from all three, and
`./lab.sh grade` passes.

Target: 20 minutes.
