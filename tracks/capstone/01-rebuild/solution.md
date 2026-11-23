# cap-01 solution

## Approach

The chain is Terraform run on `main` → `workflow_run` → `ansible.yml` job `apply` on the runner →
`site.yml`. Three gaps to close: the trigger, a login on a VM that has no `ops` yet, and doing
that without replacing the VMs that still run.

1. Publish the runner's public key (the private half stays on the jump host):

   ```bash
   jump=$(az vm show -d -g rg-{{PREFIX}}-shared -n vm-{{PREFIX}}-jump --query publicIps -o tsv)
   ssh -i ~/.ssh/{{PREFIX}}_lab azureuser@"$jump" sudo cat /home/gh-runner/.ssh/id_ed25519.pub |
     gh variable set RUNNER_SSH_PUBLIC_KEY -R {{GH_OWNER}}/{{LIVE_REPO}}
   ```

2. Modules repo, PR → merge → tag `v3.2.0` → push the tag. In `linux-vm`:

   ```hcl
   variable "extra_ssh_public_keys" {
     type    = list(string)
     default = []
     # + description, and a validation like ssh_public_key's
   }

   # in azurerm_linux_virtual_machine.this, after the admin_ssh_key block for ssh_public_key:
   dynamic "admin_ssh_key" {
     for_each = setsubtract(toset([for k in var.extra_ssh_public_keys : trimspace(k)]), [trimspace(var.ssh_public_key)])
     content {
       username   = var.admin_username
       public_key = admin_ssh_key.value
     }
   }

   lifecycle {
     ignore_changes = [admin_ssh_key] # first-boot logins: never replace a running VM for a key
   }
   ```

   Add a plan test with two keys, a `3.2.0` entry in `CHANGELOG.md` (Added + Changed), and the
   new input in the README.

3. Platform repo, one PR:
   - `terraform/env-dev`: `variable "runner_ssh_public_key"` (string, `default = ""`, validated:
     empty or `ssh-ed25519 …`/`ssh-rsa …`), module `"web"` on `?ref=v3.2.0` with
     `extra_ssh_public_keys = compact([trimspace(var.runner_ssh_public_key)])`.
   - `terraform.yml` and `drift.yml` env:
     `TF_VAR_runner_ssh_public_key: ${{ vars.RUNNER_SSH_PUBLIC_KEY }}`.
   - `ansible.yml`:

     ```yaml
     on:
       workflow_run:
         workflows: [terraform]
         types: [completed]
         branches: [main]

     jobs:
       apply:
         if: (github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && inputs.task == 'apply' && inputs.env == 'dev') || (github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event != 'pull_request' && github.event.workflow_run.head_repository.full_name == github.repository)) && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
         concurrency:
           group: ansible-apply
           cancel-in-progress: false
     ```

     The other jobs' `if:` conditions don't match `workflow_run`, so they're skipped.
   - `ansible/ci/runner.yml`: `ansible_user: "{{ acme_ci_login | default('ops') }}"` and
     `acme_ci_first_contact_user: azureuser`.
   - `ansible/first-contact.yml`, imported by `site.yml` right after `guard.yml`:

     ```yaml
     - name: Log in as the admin user where ops doesn't exist yet
       hosts: all
       gather_facts: false
       tasks:
         - name: Try the usual login
           ansible.builtin.ping:
           ignore_unreachable: true
           register: first_contact_ping
           when: acme_ci_first_contact_user is defined
         - name: Use the admin user on hosts the usual login can't reach yet
           ansible.builtin.set_fact:
             acme_ci_login: "{{ acme_ci_first_contact_user }}"
           when:
             - acme_ci_first_contact_user is defined
             - first_contact_ping is unreachable
     ```

     Only CI defines `acme_ci_first_contact_user`, so your own runs skip both tasks. The facts
     `set_fact` makes last for the whole run: the baseline play connects as `azureuser`, role
     `base` creates `ops` with both keys, and every later run logs in as `ops` again.

4. Read the PR plan: env-dev shows `vm-{{PREFIX}}-web-dev-2` with its NIC to add and **no change**
   to `vm-{{PREFIX}}-web-dev-1` (without `ignore_changes`, the new key would replace it). Merge,
   approve `apply-prod`. When the Terraform run completes, `ansible.yml` starts by itself
   (event `workflow_run`); its log shows `UNREACHABLE ... ignoring` for the new VM in the first
   play, then the baseline as `azureuser`.

## Verify

```bash
gh run list -R {{GH_OWNER}}/{{LIVE_REPO}} --workflow ansible.yml --limit 3   # newest: workflow_run, green
az vm show -g rg-{{PREFIX}}-dev -n vm-{{PREFIX}}-web-dev-2 \
  --query "osProfile.linuxConfiguration.ssh.publicKeys[].keyData" -o tsv      # your key + the runner's
ssh -i ~/.ssh/{{PREFIX}}_lab azureuser@"$jump" 'for i in $(seq 10); do curl -s localhost; done' | sort | uniq -c
./lab.sh grade
```

`grade` ends with `./lab.sh grade --all`: every finished task of both tracks again, Molecule
scenarios included, so it takes a while. Run `./lab.sh grade --all` yourself afterwards to see
the whole platform green.

## Cost and cleanup

Nothing new costs money: a public key in a repo variable, one more trigger, and the same VMs
(the rebuilt one replaces the deleted one). Pause when you stop, as always. After a resume
`runner-register.sh` puts the rebuilt jump host's new key into `RUNNER_SSH_PUBLIC_KEY`.
