---
id: an-09
title: The app as a systemd service
target_minutes: 25
requires: [tf-25, an-08]
---
# an-09 The app as a systemd service

The developers handed over `acme-hello`, a small Python app (standard library only), in three
releases: `1.0.0`, `1.1.0` and one that is broken on purpose. `./lab.sh next` saved them in
`~/.platform-lab/starter/an-09/releases/`. Ops rules for every service on the fleet: it runs under
systemd, never as root, as locked down as it tolerates; a deploy picks a release by version, and a
deploy only counts when the running code reports healthy with that version.

This task gets 25 minutes: a role with a hardened unit, a health-gated restart, a change to nginx
and a Molecule scenario. The app itself is given.

## Deliverables

- [ ] Role `ansible/roles/acme_hello` (variables `acme_hello_`), applied to `role_web` after
      `app_env` and before `nginx`. The releases ship in the role's
      `files/releases/<version>/acme_hello.py`.
- [ ] A fleet variable **`app_version`** (default `1.0.0`, in the web servers' group variables)
      picks the release; `-e app_version=1.1.0` deploys another. Releases sit side by side on the
      VM, and switching between them doesn't delete the others.
- [ ] systemd unit `acme-hello.service`: a dedicated non-root user (or `DynamicUser=yes`), in the
      group `acme` that may read `/etc/acme/app.env`, which the unit loads; the app listens on
      `127.0.0.1:8080` (`APP_PORT`) and shows the environment (`APP_ENV`); restarts on failure;
      hardened so that `systemd-analyze security acme-hello.service` rates it **below 5.0**.
- [ ] After any change the role restarts the app, then waits with `ansible.builtin.uri` until
      `/health` answers `ok <app_version>`. A release that doesn't get there fails the run. Try
      `-e app_version=broken` once (then deploy `1.0.0` again).
- [ ] nginx proxies every request (`/`, `/health`) to the app, on 80 and 443.
- [ ] Molecule scenario for `acme_hello`. Whatever an unprivileged container can't run is switched
      off by a documented role variable, defaults unchanged for the VMs.
- [ ] Lint-clean; a second `site.yml` run reports `changed=0`.

## Done when

On a web VM, `curl -s localhost/health` prints `ok 1.0.0` and `curl -s localhost/` names the
release, the host and `dev`; `systemctl show -p User acme-hello` isn't root; a run with
`-e app_version=broken` fails at the health check; and `./lab.sh grade` passes.

Target: 25 minutes.
