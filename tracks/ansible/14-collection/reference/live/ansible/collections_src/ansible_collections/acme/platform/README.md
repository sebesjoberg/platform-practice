# acme.platform

The Acme platform team's Ansible content, used by `ansible/site.yml` in this repo.

| Content | What it does |
|---|---|
| role `base` | baseline for every Ubuntu VM: ops user, sshd hardening, unattended upgrades, chrony |
| role `app_env` | the app's environment file and settings (values from the inventory, e.g. Key Vault) |
| role `acme_hello` | the acme-hello app as a hardened, health-gated systemd service |
| role `nginx` | nginx with a validated, role-owned config, TLS, reverse proxy |
| role `haproxy` | HAProxy load balancer with the Runtime API at level admin |
| module `acme_app_setting` | one key in a JSON settings file, with check and diff mode |

Install a release (from `ansible/`):

```bash
ansible-galaxy collection install -r collections/requirements.yml -p collections --force
```

Develop: each role has a Molecule scenario (`cd roles/<role> && molecule test`, venv active).
Release: bump `version` in `galaxy.yml`, add a `CHANGELOG.md` entry, merge, tag the merge commit
`acme.platform-<version>`, push the tag, pin it in `ansible/collections/requirements.yml`.
