---
id: an-05
title: Molecule for the base role
target_minutes: 25
requires: [tf-25, an-04]
---
# an-05 Molecule for the base role

Right now the only test of role `base` is running it against the fleet. The team wants every role
change proven in a throwaway machine first: converge, converge again with nothing to do, then
assertions on the result, on your laptop and later in CI (an-16, on GitHub-hosted runners: the
1 GiB jump host never runs containers). Docker Desktop's WSL integration gives you the containers.

## Deliverables

- [ ] Scenario `default` in `ansible/roles/base/molecule/default/` with the **docker** driver and
      an Ubuntu 24.04 platform.
- [ ] Decide how services behave in the container, and write the decision down in
      `molecule.yml`: either a systemd-capable container (systemd as PID 1, so the sshd handler
      really runs) or a plain one where service tasks and handlers are switched off through a
      role variable that the scenario sets. Whatever needs switching off is a documented,
      `base_`-prefixed role variable, default unchanged for the VMs.
- [ ] `converge.yml` applies `base` the way `site.yml` does (with a test key for the ops user).
- [ ] `verify.yml` (the ansible verifier) asserts at least: the sshd drop-in contains
      `PermitRootLogin no` and `PasswordAuthentication no`, and `openssh-server`,
      `unattended-upgrades` and `chrony` are installed.
- [ ] The full default sequence passes: `molecule test` (create, converge, **idempotence**,
      verify, destroy). Don't drop idempotence or verify from the sequence.
- [ ] Pins: `community.docker` (exact version) in `collections/requirements.yml`; `molecule` and
      `molecule-plugins[docker]` in `requirements.txt`.
- [ ] Still lint-clean (ansible-lint lints the scenario too).

## Done when

`cd ansible/roles/base && molecule test` passes with the venv active, the VMs still converge
with `changed=0` on a second `site.yml` run, and `./lab.sh grade` passes (it runs
`molecule test`, which takes a few minutes).
