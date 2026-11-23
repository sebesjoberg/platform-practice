# Ansible track

Terraform built Acme's machines; this track configures them. You already know Ansible, so the
tasks skip playbook basics and go straight to how a platform team runs it in production: pinned
toolchains, dynamic inventory, roles with tests and lint gates, secrets from Key Vault, rolling
updates without downtime, drift detection and CI on a self-hosted runner. Most tasks take 15–20
minutes, a few bigger ones 25 (each task says its target). `./lab.sh next ansible` starts one, `./lab.sh hint` / `solution` help, and
`./lab.sh grade` checks it.

| Phase | Tasks | You build |
|---|---|---|
| A Foundation | an-01 … an-05 | pinned venv and collections, dynamic inventory through the jump host, the `base` role, lint gates, Molecule |
| B Services | an-06 … an-10 | nginx, Key Vault secrets, TLS, the app as a service, HAProxy on the jump host |
| C Operations | an-11 … an-20 | rolling updates, drift, custom modules, a collection, CI on the self-hosted runner, prod guard rails |

## Before an-01

The track starts from the **tf-25 reference state**: the jump host `vm-<prefix>-jump` (public IP,
SSH from your IP only) and the web VMs `vm-<prefix>-web-dev-1` / `-2` (private only), Ubuntu 24.04,
user `azureuser`, your key `~/.ssh/<prefix>_lab`.

- Did the Terraform track up to tf-25? You're set: `./lab.sh next ansible`.
- Only doing this track? Build that state with `./lab.sh catchup tf-25`, then `./lab.sh grade tf-25`
  (marks it done, which `next ansible` requires), then `./lab.sh next ansible`.

The VMs cost money every hour: `./lab.sh pause` when you stop, `./lab.sh resume` when you're back.
Resume brings the VMs back empty; re-run your playbooks (`ansible-playbook site.yml`).

## Conventions

Later tasks and their checks assume these. Keep them in your own code.

- **Everything lives in `ansible/`** in your `<prefix>-platform` repo: `ansible.cfg`,
  `requirements.txt`, `collections/requirements.yml`, `inventory/`, `roles/`, `site.yml`, the lint
  and pre-commit configs. `./lab.sh catchup an-XX` replaces only `ansible/` (and
  `.github/workflows/ansible*.yml`), never your Terraform code.
- **Run Ansible from `ansible/`**, so `ansible.cfg` applies. Keep the repo in your WSL home (the
  default `~/acme/...`), not under `/mnt/c`: Ansible ignores an `ansible.cfg` in a world-writable
  directory, and every Windows-drive directory looks world-writable to WSL.
- **A pinned toolchain per repo.** `ansible/.venv` (gitignored) is built from
  `ansible/requirements.txt`, which pins `ansible-core` 2.21.x (the newest line on WSL's Python
  3.12) and, from an-04/an-05, the linters and Molecule. Collections are pinned by exact version in
  `ansible/collections/requirements.yml` and installed into `ansible/collections` (gitignored),
  never into `~/.ansible`. The checks use `ansible/.venv`; activate it with
  `source ansible/.venv/bin/activate`.
- **Inventory = Azure.** `ansible/inventory/azure_rm.yml` (the `azure.azcollection.azure_rm`
  plugin, your `az login` locally) names hosts after their VMs and groups them by the `role` and
  `env` tags: `role_jump`, `role_web`, `env_hub`, `env_dev`. Plays target groups, never IPs. The web
  VMs are reached through the jump host, whose IP comes from the inventory.
- **Roles are role-prefixed and lint-clean.** Variables of role `base` start with `base_`;
  `ansible-lint` passes with the `production` profile (an-04); every role has a Molecule scenario
  that converges, is idempotent and verifies (an-05).
- **Idempotent or it isn't done.** A second `ansible-playbook site.yml` reports `changed=0` on every
  host; graders run it.
- **Changes go through pull requests**, as in the Terraform track (`main` is protected). The
  Terraform pipeline runs on every pull request and merge, Ansible-only ones too: the plan says
  `No changes.`, and after the merge approve `apply-prod` (it changes nothing). A rejected or failed
  run leaves `main` red, and `./lab.sh catchup an-XX` treats a red tf-25 state as missing and
  replays the Terraform reference.
- **No secrets in the repo** (public). Keys stay in `~/.ssh`; secrets come from Key Vault (an-07).
