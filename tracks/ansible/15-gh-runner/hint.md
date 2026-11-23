# an-15 hints

Docs:
- Adding a self-hosted runner, `config.sh` options: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners
- The runner as a service (`svc.sh`): https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service
- Registration token API: https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository
- Fork pull request approval: https://docs.github.com/en/rest/actions/permissions
- Self-hosted runner security (public repos): https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#hardening-for-self-hosted-runners

Traps:
- **The token lives an hour and is a secret.** Hand it over in a file outside the repo, mode 0600,
  so it appears in no command line either:
  `gh api -X POST repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runners/registration-token --jq '{gh_runner_token: .token}' > /tmp/t.json`,
  then `ansible-playbook runner.yml -e @/tmp/t.json`. `no_log: true` on the task that uses it.
- **Idempotent registration:** `config.sh` writes `.runner`; `creates:` on that file skips the
  registration once done. `--replace` lets a rebuilt jump host take over its old name.
- **`config.sh` refuses to run as root.** `become_user: gh-runner` on that task; Ansible then
  needs `acl` on the host to hand the module over to an unprivileged user. `svc.sh install
  gh-runner` runs as root and writes the unit's name to `.service`.
- **`ansible.builtin.user` can make the key**: `generate_ssh_key: true`, `ssh_key_type: ed25519`.
  It never overwrites an existing key.
- **Authorizing the key everywhere:** `base` manages `ops`' keys exclusively, so the runner's key
  must be in `base_ops_authorized_keys` on every run, or the next run removes it again. Read it
  with `slurp` in a `pre_task`, `delegate_to` the jump host, `run_once`, and add it when it
  exists (before the runner exists there is none). Delegation works with `--limit` too.
- **The runner reaches the jump host itself** through its private IP, as `ops`, with the same
  key (an-16): authorizing on all hosts, not just the web VMs, is deliberate. It also means the
  runner's jobs can become root everywhere, which is what a CI that applies config needs. Hence
  the fork approval.
- **Runner dependencies on Ubuntu 24.04:** `libicu74`, `libkrb5-3`, `zlib1g`, `libssl3t64`,
  `liblttng-ust1t64`. `bin/Runner.Listener --version` as the runner's user proves them (a good
  Molecule verify step).
- **The release:** the role goes into the collection, so it is a new collection version. Merge,
  tag `acme.platform-1.1.0`, push the tag, then bump the pin and reinstall with `--force`.
- **Swap in a container fails**: a role variable (size 0 = off) that only the scenario sets.
