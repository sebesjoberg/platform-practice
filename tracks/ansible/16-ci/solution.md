# an-16 solution

## Approach

One workflow. GitHub-hosted jobs lint and run Molecule; runner jobs check, apply and detect drift.
The runner jobs build a cached toolchain, then run the same playbooks you run, with one extra
variables file that describes how the jump host reaches the fleet, and with the managed identity
for Azure. No secrets: the identity and the runner's own key are the credentials.

## Code

`ansible/ci/runner.yml`:

```yaml
---
ansible_host: "{{ private_ipv4_addresses | default([inventory_hostname]) | first }}"
ansible_user: ops
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
acme_ssh_via_jump: false
acme_lab_pubkey: "{{ lookup('ansible.builtin.env', 'SSH_PUBLIC_KEY') }}"
```

`inventory/group_vars/role_web.yml`, the jump hop made switchable:

```yaml
acme_ssh_via_jump: true
jump_host_ip: "{{ hostvars[groups['role_jump'] | first]['public_ipv4_address'] | first }}"
acme_jump_proxy_args: >-
  -o ProxyCommand="ssh -W %h:%p -q
  -i {{ ansible_ssh_private_key_file }} -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  {{ ansible_user }}@{{ jump_host_ip }}"
ansible_ssh_common_args: "{{ acme_jump_proxy_args if acme_ssh_via_jump | bool else '' }}"
```

`ansible/bin/ci-toolchain.sh` (runs in each runner job): a venv under
`~/.cache/acme-ansible/<hash of the two pin files>` with `ansible-core`, the collections and the
Azure SDK, built in place and marked complete; it adds the venv to `GITHUB_PATH` and the
collections to `ANSIBLE_COLLECTIONS_PATH` (`GITHUB_ENV`) and removes older toolchains.

`.github/workflows/ansible.yml` (abridged: the drift job's issue steps are tf-27's, with the label
`ansible-drift`):

```yaml
name: ansible
on:
  pull_request:
    paths: ["ansible/**", ".github/workflows/ansible.yml"]
  push:
    branches: [main]
    paths: ["ansible/**", ".github/workflows/ansible.yml"]
  schedule:
    - cron: "41 5 * * 1-5"
  workflow_dispatch:
    inputs:
      env: {description: Environment, type: choice, options: [dev], default: dev}
      task: {description: What to run, type: choice, options: [apply, drift], default: apply}

permissions:
  contents: read

jobs:
  lint:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: {persist-credentials: false}
      - uses: actions/setup-python@v5
        with: {python-version: "3.12"}
      - working-directory: ansible
        run: |
          pip install -r requirements.txt
          ansible-galaxy collection install -r collections/requirements.yml -p collections
          yamllint --strict -c .yamllint .
          ansible-lint

  molecule:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        role: [base, app_env, acme_hello, nginx, haproxy, gh_runner]
    steps:
      # checkout, setup-python, pip + galaxy install as in lint
      - working-directory: ansible/collections_src/ansible_collections/acme/platform/roles/${{ matrix.role }}
        run: molecule test

  check:
    if: github.event_name == 'pull_request' && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: [self-hosted, acme-jump]
    env:
      ANSIBLE_AZURE_AUTH_SOURCE: msi
      AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      SSH_PUBLIC_KEY: ${{ vars.SSH_PUBLIC_KEY }}
    steps:
      - uses: actions/checkout@v4
        with: {persist-credentials: false}
      - run: bash ansible/bin/ci-toolchain.sh
      - working-directory: ansible
        run: ansible-playbook site.yml --check --diff -e @ci/runner.yml -e acme_kv_auth_source=msi

  apply:
    if: (github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && inputs.task == 'apply' && inputs.env == 'dev')) && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: [self-hosted, acme-jump]
    # env and the first two steps as in check
    steps:
      - working-directory: ansible
        run: ansible-playbook site.yml -e @ci/runner.yml -e acme_kv_auth_source=msi

  drift:
    if: (github.event_name == 'schedule' || (github.event_name == 'workflow_dispatch' && inputs.task == 'drift')) && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: [self-hosted, acme-jump]
    permissions:
      contents: read
      issues: write
    steps:
      - id: drift
        working-directory: ansible
        run: |
          rc=0
          bin/drift-check.sh -e @ci/runner.yml -e acme_kv_auth_source=msi >"$RUNNER_TEMP/drift.log" 2>&1 || rc=$?
          cat "$RUNNER_TEMP/drift.log"
          echo "rc=$rc" >>"$GITHUB_OUTPUT"
      # rc == 2: gh label create ansible-drift --force; comment on the open issue or create one
      # rc == 0: close open ansible-drift issues
      # rc != 0: exit 1
```

## Commands

```bash
cd "$LIVE_DIR" && git switch -c ansible-ci
# write the workflow, ci/runner.yml, bin/ci-toolchain.sh (chmod +x), the role_web.yml switch
git add -A && git commit -m "ci: Ansible pipeline on the self-hosted runner"
git push -u origin ansible-ci && gh pr create --fill
gh pr checks --watch                  # lint, molecule (6), check: the diff is in the check log
gh pr merge --squash --delete-branch
gh run watch "$(gh run list --workflow ansible.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
gh workflow run ansible.yml -f task=drift && sleep 10 && gh run watch "$(gh run list --workflow ansible.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh secret list; gh secret list --env prod; gh secret list --app dependabot   # only LEARNER_IP, BUDGET_EMAIL
```

The first runner job takes a few minutes longer: it builds the toolchain (the Azure SDK).

## Verify

`./lab.sh grade`. From now on `./lab.sh resume` dispatches this workflow; after a resume the jump
host is new, so first bring the runner back (`tracks/ansible/lib/runner-register.sh`).
