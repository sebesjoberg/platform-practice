# an-15 solution

## Approach

A role that installs and registers the runner like the docs say, but idempotently: user and key
first (`ansible.builtin.user` generates the ed25519 key), the pinned release unpacked once,
`config.sh` guarded by `creates: .runner` with the token under `no_log`, `svc.sh install` guarded
by `creates: .service`. The runner gets its own playbook, released in collection `1.1.0`.
`site.yml` reads the public key on the jump host on every run and adds it to `ops`' keys.

## Code

`roles/gh_runner/defaults/main.yml` (abridged):

```yaml
gh_runner_token: ""
gh_runner_name: "{{ inventory_hostname }}"
gh_runner_labels: [acme-jump]
gh_runner_user: gh-runner
gh_runner_dir: /opt/actions-runner
gh_runner_version: "2.338.2"
gh_runner_checksum: "sha256:baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
gh_runner_packages: [acl, git, python3-venv, gh, libicu74, libkrb5-3, zlib1g, libssl3t64, liblttng-ust1t64]
gh_runner_swap_mb: 2048
gh_runner_register: true
```

`roles/gh_runner/tasks/main.yml` (the key parts; swap file and package tasks omitted):

```yaml
- name: Create the runner's user, with its own SSH key
  ansible.builtin.user:
    name: "{{ gh_runner_user }}"
    shell: /bin/bash
    create_home: true
    generate_ssh_key: true
    ssh_key_type: ed25519
    ssh_key_file: .ssh/id_ed25519

- name: Download the runner release
  ansible.builtin.get_url:
    url: "https://github.com/actions/runner/releases/download/v{{ gh_runner_version }}/actions-runner-linux-x64-{{ gh_runner_version }}.tar.gz"
    dest: "/var/cache/actions-runner-linux-x64-{{ gh_runner_version }}.tar.gz"
    checksum: "{{ gh_runner_checksum }}"
    mode: "0644"

- name: Unpack the runner
  ansible.builtin.unarchive:
    src: "/var/cache/actions-runner-linux-x64-{{ gh_runner_version }}.tar.gz"
    dest: "{{ gh_runner_dir }}"
    remote_src: true
    owner: "{{ gh_runner_user }}"
    group: "{{ gh_runner_user }}"
    creates: "{{ gh_runner_dir }}/config.sh"

- name: Registration
  when: gh_runner_register
  block:
    # stat .runner + assert that a token was passed when it is missing
    - name: Register the runner with the repository
      ansible.builtin.command:
        argv: [./config.sh, --unattended, --url, "{{ gh_runner_repo_url }}",
               --token, "{{ gh_runner_token }}", --name, "{{ gh_runner_name }}",
               --labels, "{{ gh_runner_labels | join(',') }}", --work, _work, --replace]
        chdir: "{{ gh_runner_dir }}"
        creates: "{{ gh_runner_dir }}/.runner"
      become_user: "{{ gh_runner_user }}"
      no_log: true

    - name: Install the runner as a systemd service that runs as its user
      ansible.builtin.command:
        cmd: ./svc.sh install {{ gh_runner_user }}
        chdir: "{{ gh_runner_dir }}"
        creates: "{{ gh_runner_dir }}/.service"
    # slurp .service, then systemd_service: name=<its content>, state=started, enabled=true
```

Molecule: `converge.yml` sets `gh_runner_register: false` and `gh_runner_swap_mb: 0`; `verify.yml`
checks the key (owner `gh-runner`, `0600`, `ssh-ed25519`) and runs
`bin/Runner.Listener --version` as `gh-runner`. `galaxy.yml` → `1.1.0`, `CHANGELOG.md` entry.

`inventory/group_vars/role_jump.yml`: `gh_runner_repo_url: https://github.com/{{GH_OWNER}}/{{LIVE_REPO}}`.

`ansible/runner.yml`:

```yaml
- name: Self-hosted GitHub Actions runner
  hosts: role_jump
  become: true
  roles:
    - role: acme.platform.gh_runner
```

`site.yml`, the baseline play:

```yaml
  pre_tasks:
    - name: Read the CI runner's public SSH key on the jump host
      ansible.builtin.slurp:
        src: "{{ acme_runner_pubkey_file }}"
      delegate_to: "{{ groups['role_jump'] | first }}"
      run_once: true
      register: acme_runner_pubkey
      failed_when: >-
        acme_runner_pubkey is failed
        and 'file not found' not in (acme_runner_pubkey.msg | default('') | lower)
    - name: Stop unless the runner's key was read or doesn't exist yet
      ansible.builtin.assert:
        that: >-
          acme_runner_pubkey.content is defined
          or 'file not found' in (acme_runner_pubkey.msg | default('') | lower)
        fail_msg: >-
          Could not read {{ acme_runner_pubkey_file }} on the jump host; role base would remove
          the CI runner's key from every VM. Fix the jump host, then run again.
        quiet: true
```

Only a missing file (no runner yet) may pass. `failed_when: false` would also swallow a jump host
that times out or a permission error: base then runs with your lab key alone and, being
exclusive, strips the runner's key from every VM, and CI is locked out until the next good run.
An unreachable jump host isn't a task failure at all (`failed_when` never sees it), hence the
assert every host runs before base.

`inventory/group_vars/all.yml`:

```yaml
acme_lab_pubkey: "{{ lookup('ansible.builtin.file', '~/.ssh/{{PREFIX}}_lab.pub') }}"
acme_runner_pubkey_file: /home/gh-runner/.ssh/id_ed25519.pub
base_ops_authorized_keys: >-
  {{ [acme_lab_pubkey | trim]
  + ([acme_runner_pubkey.content | b64decode | trim] if (acme_runner_pubkey | default({})).content is defined else []) }}
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd collections_src/ansible_collections/acme/platform/roles/gh_runner && molecule test)
ansible-lint
# PR with the role and galaxy.yml 1.1.0; merge; then on main:
git tag -a acme.platform-1.1.0 -m "acme.platform 1.1.0" && git push origin acme.platform-1.1.0
# pin acme.platform-1.1.0 in collections/requirements.yml (PR), then:
ansible-galaxy collection install -r collections/requirements.yml -p collections --force

umask 077
gh api -X POST repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runners/registration-token \
  --jq '{gh_runner_token: .token}' > /tmp/runner-token.json
ansible-playbook runner.yml -e @/tmp/runner-token.json && rm /tmp/runner-token.json
ansible-playbook site.yml          # authorizes the runner's key
ansible-playbook site.yml          # changed=0

gh api -X PUT repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/runners --jq '.runners[] | {name, status, labels: [.labels[].name]}'
```

## Verify

`./lab.sh grade`. After `./lab.sh pause` / `resume` the jump host is new: the old runner shows
offline in GitHub until you register the new one (`tracks/ansible/lib/runner-register.sh` from the
lab directory does both steps above).
