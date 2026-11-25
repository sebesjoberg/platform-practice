# Ansible track

Terraform built Acme's machines; this track configures them. You already know Ansible, so the
tasks skip playbook basics and go straight to how a platform team runs it in production: pinned
toolchains, dynamic inventory, roles with tests and lint gates, secrets from Key Vault, rolling
updates without downtime, drift detection and CI on a self-hosted runner. Most tasks take 15–20
minutes, a few bigger ones 25. `./lab.sh next ansible` starts one, `./lab.sh hint` / `solution` help, and
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
- Only doing this track? Build that state with `./lab.sh catchup tf-25` (it marks tf-01 … tf-25
  done, which `next ansible` requires), then `./lab.sh next ansible`.

The VMs cost money every hour: `./lab.sh pause` when you stop, `./lab.sh resume` when you're back.
Resume brings the VMs back empty and, from an-07 on, an empty dev Key Vault. `./lab.sh resume`
waits for the Terraform run (approve `apply-prod` when it asks), restores the vault contents your
tasks need (a new `app-greeting` secret, your certificate role and a new `web-tls` certificate)
and re-runs `site.yml` from `ansible/.venv`. If that last part fails (a playbook error, a run that
took too long), the lab stays paused: fix it and run `./lab.sh resume` again, or redo it by hand:
`tracks/ansible/lib/keyvault-prereqs.sh` from the lab directory, then
`cd "$LIVE_DIR/ansible" && source .venv/bin/activate && ansible-playbook site.yml`.

**From an-15 on** the jump host is also your self-hosted GitHub runner, and a resumed jump host is
a new machine: GitHub shows the old runner offline. So instead of `site.yml`, resume runs
`tracks/ansible/lib/runner-register.sh`: it cancels pipeline runs waiting for a runner (they
would start on the new runner before the fleet knows its key), registers the new jump host with a
fresh token (`runner.yml`), puts back the Key Vault objects, runs `site.yml`, which authorizes the
runner's new SSH key on every VM, and re-runs the cancelled runs the Terraform pipeline had
triggered (cap-01). From an-16 on resume then dispatches the Ansible pipeline (`-f env=dev`). If
it fails, run the script yourself from the lab directory.

## Conventions

Later tasks and their checks assume these. Keep them in your own code.

- **Everything lives in `ansible/`** in your `<prefix>-platform` repo: `ansible.cfg`,
  `requirements.txt`, `collections/requirements.yml`, `inventory/`, the roles (`roles/` until
  an-14, then the collection source in `collections_src/`), the playbooks (`site.yml`,
  `rolling.yml`/`deploy.yml`, `runner.yml`, `compliance.yml`), `bin/`, `ci/`, the lint and
  pre-commit configs. The pipeline is `.github/workflows/ansible.yml` (an-16).
  `./lab.sh catchup an-XX` replaces only `ansible/` (and `.github/workflows/ansible*.yml`), never
  your Terraform code.
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
- **From an-14 the roles and the module are a collection, `acme.platform`**, whose source is
  `ansible/collections_src/ansible_collections/acme/platform`. Playbooks use the *release* (FQCNs,
  `acme.platform.base`), installed from git by tag (`acme.platform-X.Y.Z`) through
  `collections/requirements.yml` like any other collection; Molecule tests the source. A role
  change is a release: bump `galaxy.yml`, add a `CHANGELOG.md` line, merge, tag the merge commit,
  push the tag, pin it, `ansible-galaxy collection install ... --force`. Released tags never move.
- **Idempotent or it isn't done.** A second `ansible-playbook site.yml` reports `changed=0` on every
  host; graders run it. From an-12, `bin/drift-check.sh` (`site.yml --check --diff`) tells drift
  (exit 2) from a failed check (exit 1); check mode must work for every task.
- **Changes go through pull requests**, as in the Terraform track (`main` is protected). Since
  tf-24 the Terraform pipeline skips its work for a pull request or merge that touches no
  Terraform path: an Ansible-only change gets a green `plan`, skipped `apply` jobs and no prod
  approval to give. From an-16 the Ansible pipeline does the rest (below).
- **Prod is guarded** (an-19). `env_prod` exists (empty: the lab builds no prod VMs), and
  `site.yml`/`deploy.yml` refuse any run that includes a prod host unless it says
  `-e confirm_prod=true`. Dev runs say `--limit env_dev:env_hub`; plain runs work as long as
  `env_prod` is empty. The dev load balancer only ever gets `role_web` ∩ `env_dev`.
- **Speed settings** (an-17): pipelining, long-lived SSH connections, and a fact cache in
  `ansible/.facts/` (gitignored). After a resume the VMs are new: `rm -rf ansible/.facts` if facts
  look stale. Never cache a fact that holds a secret (`cacheable: true`).
- **No secrets in the repo** (public). Keys stay in `~/.ssh`; secrets come from Key Vault (an-07).
  The `azure.azcollection.azure_keyvault_secret` lookups live in the inventory's group variables
  (vault URL per environment in `env_<name>.yml`, the auth source in `acme_kv_auth_source`: `cli`
  locally, `msi` on the runner), roles get plain values and write them with `no_log`.
- **Roles don't know where they run.** Plays target groups (`role_web`, `role_jump`); per-host and
  per-environment values (IPs, the environment name, Key Vault values) come from the inventory.
  What a container can't do in Molecule (chrony, systemd mount namespaces) is switched off by a
  documented role variable that only the scenario sets.
- **One release knob, kept in the inventory.** `app_version` in the web servers' group variables
  (`group_vars/role_web.yml`) picks the app release (an-09) and is the source of truth: a deploy
  or a rollback is a reviewed change to that line, merged, then applied. `-e app_version=…` is for
  a one-off experiment only (trying the `broken` release): the next plain `site.yml` run (graders,
  CI, drift detection) puts the inventory's version back, and reports it as a change.

## CI on the self-hosted runner (an-15 … an-20)

- **The runner** is `vm-<prefix>-jump`, registered with your repo by `runner.yml` (role
  `acme.platform.gh_runner`), labels `self-hosted` and `acme-jump`, running as user `gh-runner`.
  `runner.yml` runs from your machine only, never from CI (a runner must not restart itself
  mid-job), and needs a registration token only while the runner isn't registered.
- **Its credentials are its own.** Azure: the jump host's managed identity (Reader on the
  subscription for the inventory, Key Vault Secrets User on both vaults), so the runner jobs set
  `ANSIBLE_AZURE_AUTH_SOURCE=msi` and pass `-e acme_kv_auth_source=msi`. SSH: an ed25519 key of
  `gh-runner`, made on the jump host; `site.yml` reads its public half there and role `base`
  authorizes it for `ops` on every VM. The repo holds no secret for any of it.
- **It connects differently.** The runner is the jump host: `-e @ci/runner.yml` makes it reach
  every VM by private IP without the jump hop, as `ops` with its own key, and gives role `base`
  your lab key's public half from the repo variable `SSH_PUBLIC_KEY`, so both sides authorize the
  same keys.
- **`.github/workflows/ansible.yml`.** Pull requests: `lint` and `molecule` on GitHub-hosted
  runners (containers never run on the 1 GiB jump host), `check` (`site.yml --check --diff`) on the
  runner. Push to `main`: `apply`. Weekday mornings: `drift` (an issue labelled `ansible-drift`
  on drift). Mondays: `compliance` (the artifact `compliance-report`, an-20). `workflow_dispatch`:
  `env` (`dev`, or `prod`: job `apply-prod`, behind the `prod` environment's approval) and `task`
  (`apply`, `drift`, `compliance`). `./lab.sh resume` dispatches `-f env=dev`.
- **A rebuilt VM configures itself** (the capstone, cap-01). `ansible.yml` also runs `apply` when a
  `terraform.yml` run on `main` succeeds (`workflow_run`). New web VMs authorize the runner's key
  (repo variable `RUNNER_SSH_PUBLIC_KEY`, which `runner-register.sh` keeps current) for
  `azureuser`, and `first-contact.yml` logs in as `azureuser` wherever `ops` doesn't exist yet.
- **Forks never reach the runner.** Every runner job's `if:` requires a push, a schedule, a
  dispatch or a pull request from this repo itself, and fork pull requests from all outside
  contributors wait for approval (`all_external_contributors`).
- **The runner's toolchain** is built from the pins once (`bin/ci-toolchain.sh`, a venv per hash
  of `requirements.txt` and `collections/requirements.yml` under `~gh-runner/.cache`); the first
  job after a pin change takes a few minutes longer.
