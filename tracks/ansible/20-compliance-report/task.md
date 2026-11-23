---
id: an-20
title: Compliance report as a CI artifact
target_minutes: 20
requires: [tf-25, an-19]
---
# an-20 Compliance report as a CI artifact

The auditors' questionnaire has the usual questions: which OpenSSH and OpenSSL versions run where,
is root login over SSH really off (not "in the config", but what sshd actually uses), how locked
down are the services, when do the certificates expire. The answer should come from the machines,
every week, without anyone logging in, and land where the auditors can download it: a CI
artifact.

## Deliverables

- [ ] `ansible/compliance.yml`, read-only on the hosts, that collects from every host:
  - [ ] package versions (at least `openssh-server` and `openssl`; also `nginx`/`haproxy` where
        installed)
  - [ ] sshd's **effective** settings (`sshd -T`): `permitrootlogin`, `passwordauthentication`,
        `maxauthtries` and friends
  - [ ] the sandboxing score of the services (`systemd-analyze security`): `acme-hello`, and
        `nginx`/`haproxy` where they run
  - [ ] the TLS certificate's expiry date on the web VMs, and whether it is valid for 30 more
        days
- [ ] It writes `ansible/reports/compliance.json` on the control node:
      `{"generated": "...", "hosts": {"<inventory hostname>": {"sshd": {...}, "packages":
      {...}, "units": {"acme-hello.service": 1.9, ...}, "tls_not_after": "..."}}}`, plus a
      Markdown version for people with a verdict per host. `reports/` is gitignored.
- [ ] Hosts don't depend on each other here: pick the play strategy accordingly (an-17).
- [ ] `ansible.yml`: a job **`compliance`** on the runner (with the fork guard), on a weekly
      `schedule` and on `workflow_dispatch` with `task=compliance`, runs it for dev
      (`--limit env_dev:env_hub`) and uploads the report with `actions/upload-artifact` as
      **`compliance-report`**. The drift check keeps its own schedule.
- [ ] Lint-clean.

## Done when

`ansible-playbook compliance.yml` writes both files and `jq '.hosts | keys' reports/compliance.json`
lists the three VMs; `gh workflow run ansible.yml -f task=compliance` ends green with an artifact
`compliance-report` you can download (`gh run download`); and `./lab.sh grade` passes (it runs the
playbook here too).

Target: 20 minutes.
