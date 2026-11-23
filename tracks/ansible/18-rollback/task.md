---
id: an-18
title: Deploy with automatic rollback
target_minutes: 20
requires: [tf-25, an-17]
---
# an-18 Deploy with automatic rollback

an-11's rolling update stops at the first unhealthy server, which saves the second one, but the
first stays broken and out of the pool until someone wakes up. The developers have a release that
starts fine and answers every request with a 500 (`broken`, in the role since an-09); the next one
like it must undo itself: the server goes back to the release that ran before, rejoins the pool
healthy, and the deploy reports failure loudly.

## Deliverables

- [ ] `ansible/deploy.yml`, a play for `role_web` with `serial: 1` and `max_fail_percentage: 0`:
  - [ ] before anything changes, it finds out which release runs now (where
        `/opt/acme-hello/current` points)
  - [ ] a `block` drains the server in HAProxy (as in an-11) and deploys the release with role
        `acme.platform.acme_hello` (its health gate is the test)
  - [ ] a `rescue` switches the server back to the previous release (healthy again, through the
        same role) and then **fails the run**, with a message that names the failed release and
        the one restored
  - [ ] an `always` puts the server back into HAProxy and waits until it is `UP`, whether the
        deploy worked or not
- [ ] `rolling.yml` keeps working as an-11 left it (simplest: it imports `deploy.yml`).
- [ ] Lint-clean; after a failed deploy a `site.yml` run reports `changed=0`.

## Done when

`ansible-playbook deploy.yml -e app_version=broken` exits non-zero after rolling
`vm-{{PREFIX}}-web-dev-1` back, `vm-{{PREFIX}}-web-dev-2` is never touched, both VMs answer
`/health` with `ok 1.1.0`, `echo "show servers state web" | sudo socat stdio /run/haproxy/admin.sock`
on the jump host shows both servers in the pool, and `./lab.sh grade` passes.

Target: 20 minutes.
