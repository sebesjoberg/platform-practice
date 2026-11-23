---
id: an-06
title: The nginx role
target_minutes: 20
requires: [tf-25, an-05]
---
# an-06 The nginx role

The web VMs get a web server. The last outage on the old platform was one missing semicolon in
an nginx vhost, pushed to every server at once and reloaded into a dead config. So the rule for
this role: a configuration that doesn't pass `nginx -t` never reaches `/etc/nginx`, and nginx only
reloads when something really changed.

## Deliverables

- [ ] Role `ansible/roles/nginx`, variables prefixed `nginx_`, applied by a second play in
      `site.yml` to the group `role_web` (with `become`).
- [ ] nginx installed, running and enabled.
- [ ] The configuration is a template, written with `validate:` running `nginx -t -c %s`.
      Careful: `-c` needs a **complete** configuration (an `events` block, an `http` block), not
      a server-block snippet. Make whatever you validate the file nginx actually loads. The
      distribution's default site no longer serves port 80.
- [ ] Changes reach nginx through a **handler** that reloads it (not a restart, not a task).
- [ ] Port 80 serves a page with the server's hostname (`vm-{{PREFIX}}-web-dev-1`, ...) and its
      environment (`dev`). The environment comes from the inventory (a per-environment group
      variable file next to the env groups), not from the role.
- [ ] Molecule scenario `default` for the role (as in an-05: docker, converge, idempotence,
      verify): verify asserts at least that nginx is active and that the page names the host.
- [ ] Lint-clean, and a second `site.yml` run reports `changed=0` on every host.

## Done when

From the jump host (`ssh` to it, then `curl -s http://<web private IP>/`) each web VM answers
with its own name and `dev`; `molecule test` passes in `ansible/roles/nginx`; break the template
on purpose (a missing `;`), run `site.yml` and see the `validate` step refuse it while nginx keeps
serving the old config; `./lab.sh grade` passes.

Target: 20 minutes.
