---
id: an-16
title: Ansible CI on the self-hosted runner
target_minutes: 25
requires: [tf-25, an-15]
---
# an-16 Ansible CI on the self-hosted runner

The runner is online; now Ansible stops running from laptops. Every pull request shows what it
would change on the fleet, every merge applies, and drift (an-12) is found by a schedule instead of
the pager. Lint and Molecule stay on GitHub's runners (containers on a 1 GiB jump host are out);
everything that touches the fleet runs on the jump host, authenticated by its managed identity
and its own SSH key. No secret goes into the repo settings for any of it.

This task gets 25 minutes: one workflow with five jobs, and a connection profile for the runner.

## Deliverables

- [ ] `.github/workflows/ansible.yml`, triggered by `pull_request` and `push` to `main` (changes
      under `ansible/` and the workflow itself), a `schedule`, and `workflow_dispatch` with an
      input `env` (`dev`; `./lab.sh resume` dispatches `-f env=dev`) and an input `task`
      (`apply` by default, or `drift`). Job ids:
  - [ ] `lint` and `molecule` (pull requests, `ubuntu-latest`): `ansible-lint` and `yamllint`;
        `molecule test` for every role of the collection (a matrix)
  - [ ] `check` (pull requests): `site.yml --check --diff` against the fleet
  - [ ] `apply` (push to `main`, dispatch `task=apply`): `site.yml`
  - [ ] `drift` (schedule, dispatch `task=drift`): `bin/drift-check.sh`; on drift it opens an
        issue labelled `ansible-drift` (or comments on the open one) and fails; a clean run
        closes it
- [ ] `check`, `apply` and `drift` run on `[self-hosted, acme-jump]`, and each one's `if:` also
      contains `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`:
      pull requests from forks never reach the runner.
- [ ] Azure on the runner = the VM's managed identity: `ANSIBLE_AZURE_AUTH_SOURCE=msi` for the
      inventory and `-e acme_kv_auth_source=msi` for the Key Vault lookups. The workflow uses no
      `secrets.*` (`github.token` for the issue is fine), and the repo gets no new secret at all:
      its only secrets stay the Terraform track's `LEARNER_IP` and `BUDGET_EMAIL` (repo,
      environments and Dependabot alike).
- [ ] The runner connects differently from your laptop: it *is* the jump host. A connection
      profile (e.g. `ansible/ci/runner.yml`, passed with `-e @...`) makes it reach every VM by
      private IP without the jump hop, as `ops` with `gh-runner`'s key, and gives role `base` the
      same keys to authorize as your machine does (the lab key's public half is the repo variable
      `SSH_PUBLIC_KEY`).
- [ ] The runner builds its Ansible toolchain from the pins once and reuses it (it keeps files
      between jobs).

## Done when

A pull request that changes `ansible/` shows green `lint`, `molecule` and `check` jobs (the
`check` log shows the diff); after the merge `apply` succeeds on `vm-{{PREFIX}}-jump`;
`gh workflow run ansible.yml -f task=drift` ends green; and `./lab.sh grade` passes.
