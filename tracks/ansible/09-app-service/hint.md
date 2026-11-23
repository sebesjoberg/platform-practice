# an-09 hints

Docs:
- systemd sandboxing directives: https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Sandboxing
- `systemd-analyze security` (and `--threshold`): https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html
- `ansible.builtin.uri` with `until` / `retries`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#retrying-a-task-until-a-condition-is-met
- Handlers and `meta: flush_handlers`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html#controlling-when-handlers-run

Traps:
- **Handlers run at the end of the play.** A health check right after the "install release"
  task still talks to the old process. `meta: flush_handlers` before the `uri` task makes the
  restart happen first; then compare the body with `ok <version>`, not just status 200, or the old
  release passes the check.
- **A changed unit file needs `daemon_reload`** before the restart (put it on the handler).
- **`until` retries failed attempts too**: a 500 or a refused connection just counts as "not yet".
  Give it `retries` × `delay` that fits the app's start time, then let it fail.
- **Release switch = symlink.** `file: state=link src=releases/<v> dest=/opt/acme-hello/current`,
  and the unit runs `current/acme_hello.py`. Notify the restart from the link and the unit file.
- **Validate the version on the control node**: `(role_path ~ '/files/releases/' ~ v ~
  '/acme_hello.py') is file` in an `assert` stops a typo before anything changes.
- **Molecule:** systemd's mount-namespace sandboxing (`ProtectSystem`, `PrivateTmp`,
  `ProtectHome`, `PrivateDevices`, `ProtectKernel*`, `DynamicUser` too, which implies them) fails
  in an unprivileged container with status `226/NAMESPACE`. Put those lines behind a role variable
  the scenario sets to false; `NoNewPrivileges`, `CapabilityBoundingSet=`, `SystemCallFilter`,
  `RestrictAddressFamilies` and friends work in the container and stay on.
- **`systemd-analyze security`** lists every directive with its weight. Without the namespace part
  you can still get below 5.0; with it, around 1.
- **The service user doesn't need group `acme`.** systemd (PID 1) reads `EnvironmentFile=` as root
  before it switches to the service user; the group only matters for an app that opens the file
  itself. Least privilege: leave the user out of it. Mark the file optional (`EnvironmentFile=-…`)
  so the role also works on its own, in Molecule, without `app_env`.
- **nginx in front:** `proxy_pass http://127.0.0.1:8080;` in `location /`, plus `Host` and
  `X-Forwarded-*` headers. Keep the static page as the default when no upstream is set, so the
  nginx Molecule scenario keeps passing unchanged.
- **No curl in the container**: verify with `ansible.builtin.uri`.
