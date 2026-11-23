---
id: an-01
title: Layout, pinned toolchain
target_minutes: 15
requires: [tf-25]
---
# an-01 Layout, pinned toolchain

The VMs exist; now the operations team moves its Ansible into the platform repo. Last quarter a
laptop with a newer `ansible-core` and a floating `community.general` rewrote half a fleet's
sudoers files, and nobody could say which versions had run. The rule from now on: the repo says
exactly which Ansible and which collections run, and any machine (yours, a colleague's, CI)
rebuilds that toolchain from the repo alone.

Work in your clone of `{{LIVE_REPO}}` (`$LIVE_DIR`), on a branch, and merge it with a pull request
as usual. Nothing in this task touches the VMs yet.

## Deliverables

- [ ] A directory `ansible/` at the root of the repo; everything of this track lives in it.
- [ ] `ansible/requirements.txt` pins `ansible-core` exactly to the latest **2.21.x** (2.22 needs
      Python 3.13; WSL Ubuntu 24.04 has 3.12).
- [ ] `ansible/collections/requirements.yml` pins `azure.azcollection`, `community.general` and
      `ansible.posix`, each to an **exact** version (the current release; no ranges).
- [ ] `ansible/ansible.cfg`: collections come from `ansible/collections` and roles from
      `ansible/roles` (`collections_path`, `roles_path`), never from `~/.ansible`. Add the
      defaults you want every run to have (forks, interpreter discovery, output format).
- [ ] A virtualenv `ansible/.venv` built from `requirements.txt`, the collections installed into
      `ansible/collections`, and the Azure collection's own Python requirements installed into the
      venv (the inventory plugin needs the Azure SDK).
- [ ] `ansible/.gitignore` ignores `.venv/` and `collections/ansible_collections/`: both are
      rebuilt from the pinned files, never committed.

## Done when

From `ansible/` with the venv active, `ansible --version` reports core 2.21 with
`config file = .../ansible/ansible.cfg`, `ansible-galaxy collection list` shows the three pinned
versions under `ansible/collections`, `git status` stays clean after the installs, and
`./lab.sh grade` passes.

Target: 15 minutes.
