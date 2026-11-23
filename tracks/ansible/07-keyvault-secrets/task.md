---
id: an-07
title: Secrets from Key Vault
target_minutes: 20
requires: [tf-25, an-06]
---
# an-07 Secrets from Key Vault

The app (an-09) needs its configuration on the web servers, and part of it is secret. Your repo is
public, so the old team's habit (an encrypted vars file, its password in a wiki) is out: secrets
live in the environment's Key Vault, and Ansible reads them at deploy time. `./lab.sh next` had
the app team store one: secret `app-greeting` in `kv-{{PREFIX}}-dev-{{SUFFIX}}`, a random value
nobody pasted anywhere.

## Deliverables

- [ ] Role `ansible/roles/app_env` (variables `app_env_`): writes `/etc/acme/app.env`, owner
      `root`, group `acme` (a system group the role creates), mode `0640`, one `KEY=value` line
      per variable. The values come in as a role variable; the role knows nothing about Key
      Vault. Applied to `role_web`, before nginx.
- [ ] `APP_GREETING` is the value of `app-greeting`, read at run time with the
      `azure.azcollection.azure_keyvault_secret` lookup. The vault's URL is a per-environment
      group variable; the repo holds names, never values.
- [ ] How the lookup authenticates is a **variable**: `cli` (your `az login`) now; CI on the jump
      host (an-16) will switch it to `msi`, its managed identity, without editing a file.
- [ ] The value never shows up in output: `no_log: true` wherever it flows, so even
      `ansible-playbook site.yml --check --diff -v` prints no value.
- [ ] The value is in no file and no commit of your repo, on any branch.
- [ ] Molecule scenario for `app_env` with a stub value instead of the lookup; lint-clean; a
      second `site.yml` run reports `changed=0`.

## Done when

`sudo cat /etc/acme/app.env` on a web VM shows the value that
`az keyvault secret show --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n app-greeting --query value -o tsv`
prints, `git grep` for that value in your repo finds nothing, and `./lab.sh grade` passes.

After `./lab.sh pause` / `resume` the dev vault comes back new and empty. `./lab.sh resume` stores
a new secret and re-runs `site.yml`; if that fails, run `tracks/ansible/lib/keyvault-prereqs.sh`
from the lab directory (next to `lab.sh`), then `ansible-playbook site.yml` from `ansible/`.

Target: 20 minutes.
