---
id: an-11
title: Rolling update without a dropped request
target_minutes: 20
requires: [tf-25, an-10]
---
# an-11 Rolling update without a dropped request

Release `1.1.0` of acme-hello is approved. Last time a release went out, `site.yml` restarted both
web servers in the same minute and the status page counted 40 seconds of 502s. From now on a
release rolls: one server leaves the load balancer, gets the new code, proves it is healthy,
rejoins, and only then is the next one touched. A broken server stops the rollout while the
other one keeps serving.

## Deliverables

- [ ] `ansible/rolling.yml`, a play for `role_web` that updates **one server at a time**
      (`serial`) and stops at the first failed server (`max_fail_percentage: 0`).
- [ ] Before a server changes, it leaves HAProxy's backend `web` on the jump host through the
      Runtime API (`/run/haproxy/admin.sock`, an-10) **drained**: running requests finish, new
      ones go to the other server. The server names in the backend are the inventory hostnames.
- [ ] The release is deployed by role `acme_hello` (its health gate waits for
      `/health` = `ok <version>`).
- [ ] Afterwards the server goes back into the pool, and the play waits until HAProxy itself
      reports it `UP` before the next server leaves.
- [ ] Every HAProxy step is delegated to the load balancer **from the inventory**
      (`groups['role_jump']`), never to a host name or an IP.
- [ ] The release: `app_version: "1.1.0"` in `inventory/group_vars/role_web.yml` (the reviewed
      change). `rolling.yml -e app_version=1.0.0` stays a one-off, which the next plain run
      undoes.
- [ ] `rolling.yml` must not reload HAProxy (a reload forgets a drained state). Lint-clean.

## Done when

On the jump host, `while sleep 0.2; do curl -s -o /dev/null -w '%{http_code}\n' localhost; done`
prints nothing but `200` while you run `ansible-playbook rolling.yml -e app_version=1.0.0` and then
`ansible-playbook rolling.yml`; `curl -s localhost/health` on each web VM prints `ok 1.1.0`, and
`./lab.sh grade` passes. The grader runs exactly that: a request every 0.2 s through HAProxy during
both runs, and it counts every answer that isn't a 200.
