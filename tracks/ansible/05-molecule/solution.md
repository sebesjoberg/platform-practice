# an-05 solution

## Approach

A systemd-capable Ubuntu 24.04 container, built from the official image by a scenario
`Dockerfile.j2`, unprivileged. With systemd as PID 1 the role runs as on the VMs: the sshd drop-in
is validated, the reload handler really starts ssh, the timezone module talks to `timedatectl`.
Two things differ from a VM, and both became role changes: chrony's service is switched off with
`base_chrony_manage_service: false` (the container may not own the clock), and the role now
creates `/run/sshd` before validating, an assumption Molecule exposed.

## Code

`roles/base/molecule/default/molecule.yml`:

```yaml
---
driver:
  name: docker
platforms:
  - name: base-noble
    image: ubuntu:24.04
    dockerfile: Dockerfile.j2
    pre_build_image: false
    command: /lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /run/lock
      - /tmp
ansible:
  env:
    ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/..
    ANSIBLE_COLLECTIONS_PATH: ${MOLECULE_PROJECT_DIRECTORY}/../../collections:${ANSIBLE_COLLECTIONS_PATH:-~/.ansible/collections}
verifier:
  name: ansible
```

`roles/base/molecule/default/Dockerfile.j2`:

```dockerfile
FROM {{ item.image }}
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus python3 python3-apt sudo ca-certificates \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN systemctl mask systemd-logind.service getty.target console-getty.service systemd-udevd.service \
      systemd-udev-trigger.service systemd-firstboot.service
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
```

`roles/base/molecule/default/converge.yml`:

```yaml
---
- name: Converge
  hosts: all
  become: true
  vars:
    base_ops_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEFp2R9YvwcMACvxp7NF8Slqla26EQOZNlgDwY/5I4Gu molecule
    base_chrony_manage_service: false
  roles:
    - role: base
```

`roles/base/molecule/default/verify.yml` (excerpt; the full file also checks the ops user, the
unattended-upgrade setting and that ssh is active):

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Read the sshd drop-in
      ansible.builtin.slurp:
        src: /etc/ssh/sshd_config.d/00-hardening.conf
      register: base_verify_dropin

    - name: The drop-in turns off root and password logins
      ansible.builtin.assert:
        that:
          - "'PermitRootLogin no' in base_verify_dropin_lines"
          - "'PasswordAuthentication no' in base_verify_dropin_lines"
      vars:
        base_verify_dropin_lines: "{{ (base_verify_dropin.content | b64decode).splitlines() }}"

    - name: Gather the installed packages
      ansible.builtin.package_facts:

    - name: The baseline packages are installed
      ansible.builtin.assert:
        that: "item in ansible_facts.packages"
      loop: [openssh-server, unattended-upgrades, chrony]
```

Role changes: `defaults/main.yml` gains `base_chrony_manage_service: true` (and
`meta/argument_specs.yml` its spec); the `Keep chrony running` task and the `Restart chrony`
handler get `when: base_chrony_manage_service`; `tasks/sshd.yml` starts with:

```yaml
- name: Make sure sshd's privilege separation directory exists
  ansible.builtin.file:
    path: /run/sshd
    state: directory
    owner: root
    group: root
    mode: "0755"
```

Pins: `community.docker` `5.4.0` in `collections/requirements.yml`; `molecule==26.11.0` and
`molecule-plugins[docker]==26.11.0` in `requirements.txt`.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml -p collections
cd roles/base
molecule converge && molecule login        # look around: systemctl status ssh, sshd -T
molecule test                              # ~2 minutes; the image build is cached afterwards
cd ../.. && ansible-lint && ansible-playbook site.yml   # the VMs already have /run/sshd: changed=0
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade` (runs `molecule test`, up to 15 minutes). The containers are removed by the test;
`docker image rm molecule_local/ubuntu:24.04` frees the cached image.
