---
id: tf-25
title: VMs, and the handover to Ansible
target_minutes: 35
requires: [tf-24]
---
# tf-25 VMs, and the handover to Ansible

The operations team configures servers with Ansible, and they want three machines to start
with: a jump host they can reach from the office, and two web servers that nobody reaches
directly. Terraform builds the machines and hands them over: names, tags and access that a
dynamic inventory can rely on. Nothing inside the VMs is Terraform's business.

This task gets 35 minutes: a new module and its release, then **two** pull requests with an
apply and a prod approval each. The env stacks grant the jump VM access to their vaults, and
they find the VM with a data source, so the VM must exist before their PR is planned.

`./lab.sh next` has saved starters in `~/.platform-lab/starter/tf-25/` and created your SSH key
pair `~/.ssh/{{PREFIX}}_lab` / `~/.ssh/{{PREFIX}}_lab.pub` if it was missing:

- `linux-vm/`: `versions.tf`, `variables.tf`, `outputs.tf`, `tests/linux-vm.tftest.hcl` and a
  `README.md` whose generated section is empty. Copy:
  `cp -rn ~/.platform-lab/starter/tf-25/linux-vm "$MODULES_DIR/"`
- `live/terraform/`: `shared/variables-access.tf` (`learner_ip`, sensitive, no default;
  `ssh_public_key`) and `env-dev/variables-access.tf` (`ssh_public_key`). Copy:
  `cp -rn ~/.platform-lab/starter/tf-25/live/terraform/. "$LIVE_DIR/terraform/"`

## Deliverables

**Modules repo.** `linux-vm/main.tf` so that `terraform test` passes: a NIC `<name>-nic` in
`var.subnet_id`, an optional Standard static public IP (`var.public_ip_name`), and an
`azurerm_linux_virtual_machine` from Canonical `ubuntu-24_04-lts` / `server`, size `var.size`,
password authentication off, one `admin_ssh_key`, optional system-assigned identity. Generate
the README section, add a `2.2.0` changelog entry and the README table row; CI green, tag
`v2.2.0`.

**Repo settings.** Your IP as a **secret** (masked in the public run logs), your public key as a
variable (it's public anyway):

```bash
gh secret set LEARNER_IP -R {{GH_OWNER}}/{{LIVE_REPO}} --body {{LEARNER_IP}}
gh variable set SSH_PUBLIC_KEY -R {{GH_OWNER}}/{{LIVE_REPO}} < ~/.ssh/{{PREFIX}}_lab.pub
```

**PR 1: the machines.** Merge it, let `apply` finish, approve `apply-prod`.

- [ ] Workflow env: `TF_VAR_learner_ip: ${{ secrets.LEARNER_IP }}` and
      `TF_VAR_ssh_public_key: ${{ vars.SSH_PUBLIC_KEY }}`.
- [ ] `terraform/shared` (with the starter's `variables-access.tf`):
  - `vm-{{PREFIX}}-jump` in `rg-{{PREFIX}}-shared`, NIC in the hub's `snet-runner`, public IP
    `pip-{{PREFIX}}-jump`, system-assigned identity, tags `role = "jump"`, `env = "hub"`
  - an inbound rule on `nsg-{{PREFIX}}-hub-runner` (landing-zone's NSG, found with a data
    source): TCP 22 from `{{LEARNER_IP}}/32` only
  - `Reader` on the subscription for the jump VM's identity
  - output `jump_public_ip`
- [ ] `terraform/env-dev` (with the starter's `variables-access.tf`): `vm-{{PREFIX}}-web-dev-1`
      and `vm-{{PREFIX}}-web-dev-2` in `rg-{{PREFIX}}-dev`, NICs in `snet-app`, **no** public
      IP, tags `role = "web"`, `env = "dev"`; output `web_private_ips`.

**PR 2: the jump host reads the vaults.** Merge, apply, approve.

- [ ] `terraform/env-dev` and `terraform/env-prod`: `Key Vault Secrets User` on the stack's own
      vault for the jump VM's identity. A `data "azurerm_virtual_machine"` finds the VM, which
      is why this can't be in PR 1: its plan would look for a VM that doesn't exist yet.

All VMs: `Standard_B2ats_v2`, Ubuntu 24.04 LTS, admin user `azureuser`, SSH key only.

## Done when

```bash
key=~/.ssh/{{PREFIX}}_lab
ssh -i $key -o "ProxyCommand=ssh -i $key -W %h:%p azureuser@<jump_public_ip>" \
  azureuser@<first web_private_ip> 'curl -fsS -o /dev/null http://archive.ubuntu.com/ubuntu/ && echo apt reachable'
```

works, and `./lab.sh grade` passes.

Target: 35 minutes.

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
- **What the Ansible track adds to this code** (in your Terraform repo, through the pipeline):
  `Key Vault Certificates Officer` for you on the vaults, to import the TLS certificate (an-08),
  and an inbound rule for TCP 80 from your IP on `nsg-{{PREFIX}}-hub-runner`, when the jump host
  becomes the load balancer (an-10).
- **The jump host has 1 GiB of memory.** It runs HAProxy and, later, a self-hosted GitHub
  runner that only does check/diff/apply runs. Molecule (containers) runs on GitHub-hosted
  runners, never on the jump host.
- **Your IP changes** (new network, new lease): run `./lab.sh init --refresh-ip`, set the repo
  secret `LEARNER_IP` to the new address, and re-run the pipeline for `shared`
  (`gh workflow run terraform.yml -f stacks=shared`).
- **The pause rule matters now.** Three VMs and a public IP cost money every hour:
  `./lab.sh pause` when you stop, `./lab.sh resume` when you're back (approve `apply-prod`).
  Resume brings the VMs back empty; the Ansible track's playbooks configure them again.
- `./lab.sh next ansible` checks that this state exists before the first Ansible task; without
  it, `./lab.sh catchup tf-25` builds it.
