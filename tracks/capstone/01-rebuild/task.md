---
id: cap-01
title: Rebuild without hands
target_minutes: 45
requires: [tf-31, an-20]
---
# cap-01 Rebuild without hands

Read the message `./lab.sh next` printed: `vm-{{PREFIX}}-web-dev-2` is gone, with its disk and NIC.
Bringing it back by hand is easy, and it's exactly what the CTO doesn't want: "When a VM
disappears, the platform puts it back. Terraform rebuilds it, Ansible configures it, HAProxy
takes it back. Nobody logs in to anything."

Both pipelines exist; they just don't talk to each other. And there's a catch: the runner logs
in as `ops`, which only role `base` creates. A VM that Terraform has just built has nothing but
`azureuser` and your lab key. The run has to get in anyway, and no private key may leave the
machine it was made on.

This capstone gets 45 minutes: it touches both repos and both pipelines.

## Deliverables

- [ ] **The Terraform pipeline triggers the Ansible pipeline.** `ansible.yml` starts when a
      `terraform.yml` run on `main` completes (`workflow_run`; a `repository_dispatch` sent by
      the apply job is fine too). Job `apply` runs for it only after a *successful* Terraform run
      that wasn't a pull request's and ran in this repo. The fork guard stays.
- [ ] **The runner's key is published, not copied.** Repo variable `RUNNER_SSH_PUBLIC_KEY` = the
      public half of `gh-runner`'s key, `/home/gh-runner/.ssh/id_ed25519.pub` on
      `vm-{{PREFIX}}-jump`.
- [ ] **Module release `v3.2.0`** of `linux-vm` in `{{MODULES_REPO}}`: input
      `extra_ssh_public_keys` (list, default `[]`), authorized for the admin user next to
      `ssh_public_key`. Changing the keys must not replace a running VM: they're first-boot
      logins, and after that the keys are Ansible's business. `CHANGELOG.md` entry, tag `v3.2.0`.
- [ ] **New web VMs trust the runner.** env-dev's web VMs on `linux-vm?ref=v3.2.0` authorize
      `RUNNER_SSH_PUBLIC_KEY` for `azureuser`: variable `runner_ssh_public_key` (default `""`:
      no extra key), set by `TF_VAR_runner_ssh_public_key` from the repo variable in
      `terraform.yml` (and `drift.yml`, which plans with the same variables).
- [ ] **First contact in CI.** A play that `site.yml` imports right after the guard tries every
      host with the usual login and, where that fails, logs in as `azureuser` for the rest of the
      run, with the same key. Role `base` then creates `ops`; the next run uses `ops` everywhere.
      Runs from your machine don't change.
- [ ] **Prove it.** Merge, approve `apply-prod` as usual, and watch: the Terraform run rebuilds
      `vm-{{PREFIX}}-web-dev-2`, the `ansible.yml` run it triggers configures it, and HAProxy has
      both backends again. No `ssh`, no `ansible-playbook`, no `gh workflow run ansible.yml`.
- [ ] `./lab.sh grade --all` reports no regressions in either track.

## Done when

`gh run list --workflow ansible.yml` shows a green `workflow_run` run that started after the new
VM, `for i in $(seq 10); do curl -s localhost; done` on the jump host names both web VMs, and
`./lab.sh grade` passes (it runs `grade --all` too, so give it time).

Target: 45 minutes.
