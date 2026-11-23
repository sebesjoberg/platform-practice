# an-05 hints

Docs:
- Molecule configuration and the test sequence: https://docs.ansible.com/projects/molecule/configuration/
- The docker driver (platform options such as `cgroupns_mode`, `tmpfs`, `dockerfile`): https://github.com/ansible-community/molecule-plugins
- `ansible.builtin.assert`, `package_facts`, `slurp`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/index.html

Traps:
- **systemd in Docker Desktop** works without `privileged`: systemd as the command, the host's
  cgroup tree (`cgroupns_mode: host`, volume `/sys/fs/cgroup:/sys/fs/cgroup:rw`) and tmpfs on
  `/run`, `/run/lock`, `/tmp`. The plain `ubuntu:24.04` image has no systemd and no Python: give the
  platform a `Dockerfile.j2` that installs `systemd`, `dbus` (for `timedatectl`), `python3` and
  `sudo`, and nothing the role installs.
- **chrony can't run in a container.** Its unit requires `CAP_SYS_TIME` (a container shares the
  host's kernel clock), so `systemctl start chrony` "succeeds" without starting it, and
  `state: started` reports changed on every run: idempotence fails. Switch the chrony service
  (task and handler) off with a role variable that the scenario sets, never by making the
  container privileged (chronyd would then set Docker's VM clock).
- **Molecule finds hidden assumptions.** `sshd -t` refuses to run without `/run/sshd`, which only
  exists after ssh.service has started. On a VM you reach over SSH it always has; in a fresh
  container it hasn't, so `validate:` fails. Make the role create the directory: that's a real
  fix, not a test workaround.
- **Molecule ignores `ansible/ansible.cfg`**: it writes its own config. Tell it where the roles
  and collections are (`ansible.env` in `molecule.yml`: `ANSIBLE_ROLES_PATH`,
  `ANSIBLE_COLLECTIONS_PATH`, built from `${MOLECULE_PROJECT_DIRECTORY}`), so `converge.yml` can
  apply `base` like `site.yml` does.
- **Role name check.** Molecule's prerun names the role `namespace.role_name` from `meta/main.yml`;
  an author with spaces is not a valid namespace. Set `galaxy_info.namespace` and `role_name`.
- **ansible-lint lints `molecule/` as part of the role**: registered variables in `verify.yml`
  need the `base_` prefix too.
- **The docker driver needs `community.docker`** on the collections path (it creates the
  containers with it), and `molecule-plugins[docker]` in the venv.
- **Stuck state:** `molecule destroy` (or `molecule reset`) after an aborted run.
