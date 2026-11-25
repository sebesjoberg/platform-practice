---
id: an-15
title: The jump host as a self-hosted runner
target_minutes: 25
requires: [tf-25, an-14]
---
# an-15 The jump host as a self-hosted runner

Ansible should run from CI (an-16), not from laptops. GitHub's own runners can't reach the web
VMs (no public IP) and have no identity in Azure; the jump host has both: it sits in the hub,
reaches every VM privately, and its managed identity reads the inventory and the vaults. So it
becomes the repo's self-hosted runner. It needs a way into the fleet that no human key and no
repo secret provides: its own SSH key, made on the jump host and never copied anywhere. And your
repo is public, so strangers' pull requests must not get to run code on it.

This task gets 25 minutes: a role with a Molecule scenario, a collection release, and the
registration.

## Deliverables

- [ ] Role `gh_runner` (variables `gh_runner_`) in the collection, released as **`1.1.0`**
      (tag `acme.platform-1.1.0`, pinned in `requirements.yml`):
  - [ ] a dedicated user `gh-runner`; the runner (pinned release, checksum verified) runs as that
        user under systemd (the runner's `svc.sh`)
  - [ ] registered with your repo as `vm-{{PREFIX}}-jump` with the label `acme-jump` (GitHub adds
        `self-hosted`), using a registration token passed with `-e` and `no_log`, never in a file
        of the repo; a registered runner needs no token on later runs
  - [ ] an **ed25519 key for `gh-runner`**, generated on the jump host
  - [ ] the 1 GiB jump host gets a swap file (Ansible with the Azure SDK, HAProxy and the runner
        don't fit in RAM alone); no Molecule, no Docker on it
  - [ ] a Molecule scenario that converges without registering
- [ ] `ansible/runner.yml` applies the role to `role_jump`. It is not part of `site.yml`: CI must
      never reconfigure (and restart) the runner it runs on.
- [ ] Role `base` authorizes the runner's public key for `ops` on every VM, read from the jump
      host at run time by `site.yml`. No private key leaves the machine it was made on.
- [ ] Repo hardening: workflows of fork pull requests from **all** outside contributors wait for
      approval (`all_external_contributors`), set with `gh api`.
- [ ] Lint-clean; a second `site.yml` run reports `changed=0`.

## Done when

`gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runners` lists `vm-{{PREFIX}}-jump` online with
`self-hosted` and `acme-jump`; on the jump host
`sudo -u gh-runner ssh -i ~gh-runner/.ssh/id_ed25519 ops@<web private IP> true` works;
`molecule test` passes for `gh_runner`; and `./lab.sh grade` passes.
