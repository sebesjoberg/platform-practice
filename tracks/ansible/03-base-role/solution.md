# an-03 solution

## Approach

A role split by concern (`users`, `sshd`, `updates`, `time`), all variables `base_`-prefixed with
defaults, and `meta/argument_specs.yml` so a missing key list fails before anything runs. The ops
user's key comes from the inventory. Every task is declarative; the only service actions are the
two handlers.

## Code

Layout:

```text
ansible/
  site.yml
  inventory/group_vars/all.yml        # + base_ops_authorized_keys
  roles/base/
    defaults/main.yml                 # base_packages, base_ops_user: ops, base_timezone, base_ntp_pools, ...
    meta/main.yml                     # galaxy_info: namespace acme, role_name base, platforms
    meta/argument_specs.yml           # base_ops_authorized_keys required
    tasks/main.yml                    # apt, then import_tasks users/sshd/updates/time, tagged
    tasks/users.yml  tasks/sshd.yml  tasks/updates.yml  tasks/time.yml
    handlers/main.yml                 # Reload sshd, Restart chrony
    templates/sshd-hardening.conf.j2  20auto-upgrades.j2  52unattended-upgrades-local.j2  base.sources.j2
```

`tasks/sshd.yml`:

```yaml
---
- name: Harden sshd with a drop-in
  ansible.builtin.template:
    src: sshd-hardening.conf.j2
    dest: /etc/ssh/sshd_config.d/00-hardening.conf
    owner: root
    group: root
    mode: "0600"
    validate: /usr/sbin/sshd -t -f %s
  notify: Reload sshd
```

`templates/sshd-hardening.conf.j2`:

```text
# {{ ansible_managed }} (role base)
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
```

`tasks/users.yml`:

```yaml
---
- name: Create the ops user
  ansible.builtin.user:
    name: "{{ base_ops_user }}"
    groups: [sudo]
    append: true
    shell: /bin/bash
    create_home: true

- name: Authorize exactly the ops user's keys
  ansible.posix.authorized_key:
    user: "{{ base_ops_user }}"
    key: "{{ base_ops_authorized_keys | join('\n') }}"
    exclusive: true

- name: Let the ops user sudo without a password (it has none)
  ansible.builtin.copy:
    dest: "/etc/sudoers.d/90-{{ base_ops_user }}"
    content: "{{ base_ops_user }} ALL=(ALL:ALL) NOPASSWD: ALL\n"
    owner: root
    group: root
    mode: "0440"
    validate: /usr/sbin/visudo -cf %s
```

`tasks/main.yml` installs `base_packages` (`openssh-server`, `sudo`, `unattended-upgrades`,
`chrony`, `tzdata`) with `update_cache: true` and `cache_valid_time: 3600`, then imports the four
files. `tasks/updates.yml` templates `/etc/apt/apt.conf.d/20auto-upgrades`
(`APT::Periodic::Update-Package-Lists "1"; APT::Periodic::Unattended-Upgrade "1";`) and
`52unattended-upgrades-local` (`Automatic-Reboot` from `base_unattended_upgrades_reboot`).
`tasks/time.yml` sets `community.general.timezone`, adds `/etc/chrony/sources.d/base.sources`
(notify `Restart chrony`) and keeps `chrony` started and enabled.

`handlers/main.yml`:

```yaml
---
- name: Reload sshd
  ansible.builtin.systemd_service:
    name: ssh
    state: reloaded

- name: Restart chrony
  ansible.builtin.systemd_service:
    name: chrony
    state: restarted
```

`site.yml`:

```yaml
---
- name: Baseline every VM
  hosts: all
  become: true
  roles:
    - role: base
```

Added to `inventory/group_vars/all.yml`:

```yaml
base_ops_authorized_keys:
  - "{{ lookup('ansible.builtin.file', '~/.ssh/{{PREFIX}}_lab.pub') }}"
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-playbook site.yml --check --diff      # what would change (the first run on fresh VMs)
ansible-playbook site.yml
ansible-playbook site.yml                     # PLAY RECAP: changed=0 on all three
ansible all -b -m ansible.builtin.shell -a 'sshd -T | grep -E "^(passwordauthentication|permitrootlogin) "'
ansible all -e ansible_user=ops -b -m ansible.builtin.ping
ssh -i ~/.ssh/{{PREFIX}}_lab ops@<jump public IP> sudo -n true && echo ops ok
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade` (runs `site.yml` once more: on a converged fleet it changes nothing). After
`./lab.sh pause` / `resume` the VMs come back empty: run `ansible-playbook site.yml` again.
