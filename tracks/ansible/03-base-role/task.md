---
id: an-03
title: The base role
target_minutes: 25
requires: [tf-25, an-02]
---
# an-03 The base role

Security review of the new VMs: everyone logs in as `azureuser`, root may log in over SSH if
someone ever gives it a key, nobody patches, and the clocks have never been looked at. The fix
goes into one role that every VM gets, before anything else runs on them, and it has to be safe
to run again at any time: a run that changes nothing must say so.

## Deliverables

- [ ] Role `ansible/roles/base`, variables prefixed `base_`:
  - [ ] a non-root admin user whose name comes from `base_ops_user` (default `ops`): member of
        `sudo`, passwordless sudo through a file in `/etc/sudoers.d` (validated with `visudo`),
        its SSH keys managed exclusively by the role. Its key is the public half of
        `~/.ssh/{{PREFIX}}_lab`, set in the inventory's group variables, not in the role.
  - [ ] sshd hardening as a **drop-in** in `/etc/ssh/sshd_config.d/` (`PermitRootLogin no`,
        `PasswordAuthentication no`, plus what else you consider baseline), written with
        `validate: /usr/sbin/sshd -t -f %s` and applied by a **handler** that reloads ssh. The
        drop-in must win over what cloud-init put there.
  - [ ] unattended-upgrades on (daily package lists and upgrades), reboots off by default
  - [ ] chrony installed, running and enabled
  - [ ] timezone `Etc/UTC` (`base_timezone`)
- [ ] `ansible/site.yml`: one play, `hosts: all`, `become: true`, role `base`.
- [ ] Run it. Then run it again: the second run reports `changed=0` on every host.

## Done when

`sudo sshd -T` on any VM prints `passwordauthentication no` and `permitrootlogin no`,
`ansible all -e ansible_user=ops -b -m ping` works (as `ops`, through the jump host too), a second
`ansible-playbook site.yml` ends with `changed=0` for all three VMs, and `./lab.sh grade` passes
(it runs `site.yml` once more and reads the PLAY RECAP).

Target: 25 minutes.
