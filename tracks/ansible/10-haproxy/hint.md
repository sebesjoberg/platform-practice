# an-10 hints

Docs:
- HAProxy configuration manual (`server`, `option httpchk`, `stats socket`): https://docs.haproxy.org/2.8/configuration.html
- The Runtime API (`show servers state`, `set server ... state drain`): https://docs.haproxy.org/2.8/management.html#9.3
- Filters `zip`, `extract`, `dict2items`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html
- Accessing other hosts' variables (`hostvars`, `groups`): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#information-about-ansible-magic-variables

Traps:
- **Other hosts' IPs come from `hostvars`.** The jump host's play only runs on the jump host, but
  `groups['role_web']` and `hostvars[<web host>]['private_ipv4_addresses'][0]` (the azure_rm
  inventory sets it, no facts needed) are there. A dict built in `group_vars/role_jump.yml` keeps
  the role generic: `dict(names | zip(names | map('extract', hostvars, ['private_ipv4_addresses', 0])))`.
- **The jump host can't resolve the web VMs' names**: Azure's internal DNS works per VNet, and
  they are in another one. Use IPs.
- **Ubuntu's default `haproxy.cfg` already has the admin socket line**; a template that replaces
  the file must keep it (`mode 660 level admin`), or an-11 has nothing to talk to.
- **Health checks hit nginx on 80**, which proxies `/health` to the app: a broken release takes
  the server out of the pool by itself. Port 443 isn't needed between HAProxy and the web VMs.
- **Run the web play first.** HAProxy's first checks after a fresh deploy otherwise find nothing
  listening; with `fall 2 rise 2` it recovers within seconds anyway.
- **Molecule:** Ubuntu's unit bind-mounts `/dev/log` into HAProxy's chroot (`BindReadOnlyPaths`),
  which needs a mount namespace: in an unprivileged container the unit fails with `226/NAMESPACE`.
  Reset it with a drop-in behind a role variable the scenario sets. Stand-in backends: a
  `prepare.yml` that starts `python3 -m http.server` on `127.0.0.2` and `127.0.0.3` (all of 127/8
  is loopback) with `systemd-run`.
- **No public exposure.** The NSG on `snet-runner` only lets SSH in from your IP; leave it. A tunnel
  shows the result in your browser: `ssh -i ~/.ssh/{{PREFIX}}_lab -L 8080:localhost:80 azureuser@<jump IP>`.
- **Talk to the socket as root** (or as a member of group `haproxy`):
  `echo "show servers state web" | sudo socat stdio /run/haproxy/admin.sock`.
