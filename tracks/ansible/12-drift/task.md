---
id: an-12
title: Config drift incident
target_minutes: 20
requires: [tf-25, an-11]
---
# an-12 Config drift incident

`./lab.sh next` printed the on-call report: someone changed `vm-{{PREFIX}}-web-dev-2` by hand last
night, and it has been out of the load balancer since. Nobody knows what was changed. Ansible
does: the repo says what every host should look like, and a run in check mode lists exactly what
differs, without touching anything. Make that a command anyone (and later a scheduled CI job,
an-16) can run, then use it on the incident.

## Deliverables

- [ ] `ansible/bin/drift-check.sh` (executable, `bash`): runs `ansible-playbook site.yml --check
      --diff` with the `ansible-playbook` on `PATH` (it doesn't activate a venv itself; CI brings
      its own toolchain), and passes its own arguments on to `ansible-playbook` (`--limit`,
      `-e ...`). It reads the `PLAY RECAP` and exits:
  - `0` when every host reports `changed=0`
  - non-zero on drift (use `2`, so CI can tell drift from breakage)
  - non-zero when a host failed or was unreachable, or no host ran (use `1`)
- [ ] Check mode works for the whole of `site.yml`: a task that can't run in check mode must not
      fail the run (hint: role `acme_hello`'s health wait).
- [ ] Find the drift with the script, read the diff, then remediate **from the repo** (not by
      hand on the VM): afterwards the script exits `0`.
- [ ] Lint-clean; `shellcheck bin/drift-check.sh` passes if you have it.

## Done when

`bin/drift-check.sh` (from `ansible/`, venv active) exits non-zero and shows the
`worker_connections` diff and the stopped nginx on `vm-{{PREFIX}}-web-dev-2` before you fix it, and
exits `0` afterwards; both web VMs serve again through HAProxy, and `./lab.sh grade` passes. The
grader also runs your script against a stand-in `ansible-playbook` that reports a clean fleet, a
changed host and an unreachable one.
