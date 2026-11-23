---
id: an-10
title: HAProxy on the jump host
target_minutes: 20
requires: [tf-25, an-09]
---
# an-10 HAProxy on the jump host

Two web servers, and nothing that spreads traffic over them or takes a sick one out. The cloud
load balancers cost more than this lab's whole budget, so the jump host gets HAProxy: it already
sits in the hub, reaches both spokes' VMs, and has room for it. Next task (an-11) rolls out a new
release one server at a time and drains each through HAProxy's Runtime API, so that API is part
of the job now.

## Deliverables

- [ ] Role `ansible/roles/haproxy` (variables `haproxy_`), applied by a third play in `site.yml`
      to `role_jump`, after the web servers' play.
- [ ] Frontend on port 80 → backend **`web`** with both web VMs, round robin, addressed by their
      **private IPs from the inventory** (no IP in any file), HTTP health check on `/health`; a
      server failing it leaves the pool.
- [ ] Runtime API: `stats socket /run/haproxy/admin.sock mode 660 level admin`.
- [ ] The configuration is a template validated with `haproxy -c -f %s` and applied through a
      reload handler.
- [ ] Not on the internet: no NSG change. Test from the jump host itself (`curl -s localhost`) or
      through a tunnel (`ssh -L 8080:localhost:80 azureuser@<jump public IP>`, then
      `curl -s localhost:8080` on your machine).
- [ ] Molecule scenario for `haproxy` (stand-in backends are fine); lint-clean; a second
      `site.yml` run reports `changed=0`.

## Done when

On the jump host, `for i in $(seq 10); do curl -s localhost; done` shows answers from both
`vm-{{PREFIX}}-web-dev-1` and `vm-{{PREFIX}}-web-dev-2`,
`echo "show servers state web" | sudo socat stdio /run/haproxy/admin.sock` lists both, and
`./lab.sh grade` passes.

Target: 20 minutes.
