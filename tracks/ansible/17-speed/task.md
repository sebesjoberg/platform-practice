---
id: an-17
title: Faster runs
target_minutes: 15
requires: [tf-25, an-16]
---
# an-17 Faster runs

A `site.yml` run that changes nothing takes minutes, mostly waiting: a new SSH handshake (two
for the web VMs, through the jump host) for almost every task, a module file copied over before
it runs, and the facts of every host gathered again on every run. The CI runner on the jump host
pays the same, and the drift check runs every morning. Make Ansible itself faster, without
changing what it does.

## Deliverables

- [ ] Measure first: per-task timings of a `site.yml` run (`ansible.posix.profile_tasks`, already
      in your pinned `ansible.posix`), and the wall time of a second run (`time ...`).
- [ ] `ansible.cfg`:
  - [ ] **pipelining** on
  - [ ] SSH connections reused across tasks and runs (`ControlPersist` long enough for a run and
        the next one), without losing `IdentitiesOnly=yes` from `ssh_args`
  - [ ] **fact caching** with the `jsonfile` plugin in a directory inside `ansible/` that is
        gitignored, with a timeout, and `gathering = smart`
  - [ ] `forks` for a fleet larger than three hosts
- [ ] Nothing secret lands in the fact cache: no `set_fact` with `cacheable: true` (the TLS bundle
      of role `nginx` must stay uncached).
- [ ] Look at `strategy` per play: where hosts don't depend on each other, `free` lets fast hosts
      finish first. Decide where it is safe and write the reason next to it, or why `linear`
      stays.
- [ ] A second `site.yml` run still reports `changed=0`, and is faster than before.

## Done when

The second `site.yml` run is noticeably faster than your first measurement (write both numbers
in the pull request), `ls ansible/<cache dir>` shows a file per VM, `git status` stays clean, and
`./lab.sh grade` passes.

Target: 15 minutes.
