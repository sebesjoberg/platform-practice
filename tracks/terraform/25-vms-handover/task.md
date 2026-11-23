---
id: tf-25
title: VMs, and the handover to Ansible
target_minutes: 25
requires: [tf-24]
---
# tf-25 VMs, and the handover to Ansible

The operations team configures servers with Ansible, and they want three machines to start
with: a jump host they can reach from the office, and two web servers that nobody reaches
directly. Terraform builds the machines and hands them over: names, tags and access that a
dynamic inventory can rely on. Nothing inside the VMs is Terraform's business.

`./lab.sh next` has saved a starter in `~/.platform-lab/starter/tf-25/linux-vm/` (`versions.tf`,
`variables.tf`, `outputs.tf`, `tests/linux-vm.tftest.hcl`; copy it with
`cp -rn ~/.platform-lab/starter/tf-25/linux-vm "$MODULES_DIR/"`) and created your SSH key pair
`~/.ssh/{{PREFIX}}_lab` / `~/.ssh/{{PREFIX}}_lab.pub` if it was missing.

This task gets 25 minutes: one more module, then three stacks use it or grant access to it.

## Deliverables

In `{{MODULES_REPO}}`: `linux-vm/main.tf` so that `terraform test` passes: a NIC in
`var.subnet_id`, an optional Standard static public IP (`var.public_ip_name`), and an
`azurerm_linux_virtual_machine` from Canonical `ubuntu-24_04-lts` / `server`, size
`var.size` (default `Standard_B2ats_v2`), password authentication off, one `admin_ssh_key`,
optional system-assigned identity. README section, a `2.2.0` changelog entry, the README's
module table; CI green, tag `v2.2.0`.

In `{{LIVE_REPO}}`:

- [ ] Repo variables `LEARNER_IP` (`{{LEARNER_IP}}`, from your `config.env`) and
      `SSH_PUBLIC_KEY` (the content of `~/.ssh/{{PREFIX}}_lab.pub`). The workflow passes them as
      `TF_VAR_learner_ip` and `TF_VAR_ssh_public_key`. The private key never goes into a repo.
- [ ] `terraform/shared`:
  - variable `learner_ip`: no default, `sensitive = true` (PR plan comments are public),
    validated as one IPv4 address; variable `ssh_public_key`
  - `vm-{{PREFIX}}-jump` in `rg-{{PREFIX}}-shared`, NIC in the hub's `snet-runner`, public IP
    `pip-{{PREFIX}}-jump`, system-assigned identity, tags `role = "jump"`, `env = "hub"`
  - an inbound rule on `nsg-{{PREFIX}}-hub-runner` (landing-zone's NSG, found with a data
    source): TCP 22 from `{{LEARNER_IP}}/32` only
  - `Reader` on the subscription for the jump VM's identity
  - output `jump_public_ip`
- [ ] `terraform/env-dev`: `vm-{{PREFIX}}-web-dev-1` and `vm-{{PREFIX}}-web-dev-2` in
      `rg-{{PREFIX}}-dev`, NICs in `snet-app`, **no** public IP, tags `role = "web"`,
      `env = "dev"`; output `web_private_ips`.
- [ ] `terraform/env-dev` and `terraform/env-prod`: `Key Vault Secrets User` on the stack's own
      vault for the jump VM's identity (a data source finds the VM).
- [ ] One PR, merged, applied (approve `apply-prod`).

All VMs: `Standard_B2ats_v2`, Ubuntu 24.04 LTS, admin user `azureuser`, SSH key only.

## Done when

```bash
ssh -i ~/.ssh/{{PREFIX}}_lab -J azureuser@<jump_public_ip> azureuser@<first web_private_ip> \
  'curl -fsS -o /dev/null http://archive.ubuntu.com/ubuntu/ && echo apt reachable'
```

works (add the same `-i` for the jump hop in `~/.ssh/config`, or use the `ProxyCommand` from
the solution), and `./lab.sh grade` passes.

Target: 25 minutes.

## Handover to the Ansible track

From here the Ansible track takes over (the tracks can now be done in any order). What it
relies on, and what you must keep working from now on:

- **Machines.** `vm-{{PREFIX}}-jump` (`rg-{{PREFIX}}-shared`, public IP `pip-{{PREFIX}}-jump`) and
  `vm-{{PREFIX}}-web-dev-1`, `vm-{{PREFIX}}-web-dev-2` (`rg-{{PREFIX}}-dev`, private only). Ubuntu
  24.04, user `azureuser`, your key `~/.ssh/{{PREFIX}}_lab`.
- **Inventory.** Ansible's dynamic inventory (`azure.azcollection.azure_rm`) groups hosts by the
  tags `role` (`jump`, `web`) and `env` (`hub`, `dev`). Keep the tags.
- **Access.** SSH reaches the jump host from your IP only; everything else goes through it
  (ProxyJump). The jump VM's identity can read the subscription (inventory) and both vaults'
  secrets (Ansible reads secrets with it).
- **Your IP changes** (new network, new lease): run `./lab.sh init --refresh-ip`, set the repo
  variable `LEARNER_IP` to the new address, and re-run the pipeline for `shared`
  (`gh workflow run terraform.yml -f stacks=shared`).
- **The pause rule matters now.** Three VMs and a public IP cost money every hour:
  `./lab.sh pause` when you stop, `./lab.sh resume` when you're back (approve `apply-prod`).
  Resume brings the VMs back empty; the Ansible track's playbooks configure them again.
- `./lab.sh next ansible` checks that this state exists before the first Ansible task; without
  it, `./lab.sh catchup tf-25` builds it.
