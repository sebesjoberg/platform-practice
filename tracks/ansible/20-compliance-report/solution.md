# an-20 solution

## Approach

Two plays. The first runs on every host with `strategy: free` and only read-only tasks (facts,
`sshd -T`, `systemd-analyze security`, `openssl x509`), and condenses them into one fact per host.
The second runs on `localhost`, collects those facts from `hostvars` and writes JSON and
Markdown. A weekly CI job runs it on the runner for dev and uploads both files.

## Code

`ansible/compliance.yml` (the first play's tasks shortened to their modules):

```yaml
- name: Collect compliance data
  hosts: all
  become: true
  strategy: free
  vars:
    compliance_packages: [openssh-server, openssl, sudo, chrony, unattended-upgrades, nginx, haproxy, python3]
    compliance_sshd_keys: [permitrootlogin, passwordauthentication, kbdinteractiveauthentication, pubkeyauthentication, maxauthtries, x11forwarding]
    compliance_units: [acme-hello.service, nginx.service, haproxy.service]
    compliance_cert: /etc/nginx/tls/acme-web.crt
  tasks:
    # package_facts (apt), service_facts
    # command: sshd -T                                        register compliance_sshd
    # command: systemd-analyze security --no-pager {{ item }}  loop over the units that exist
    # stat the certificate; command: openssl x509 -enddate ...; openssl x509 -checkend 2592000 (rc 0/1)
    # every command: changed_when: false
    - name: Put this host's data together
      ansible.builtin.set_fact:
        compliance_host:
          env: "{{ acme_env | default('unknown') }}"
          packages: >-
            {{ dict(compliance_installed | zip(compliance_installed | map('extract', ansible_facts.packages)
            | map('first') | map(attribute='version'))) }}
          sshd: >-
            {{ dict(compliance_sshd_lines | map('regex_replace', ' .*$', '')
            | zip(compliance_sshd_lines | map('regex_replace', '^[^ ]+ ', ''))) }}
          units: >-
            {{ dict(compliance_security.results | map(attribute='item')
            | zip(compliance_security.results | map(attribute='stdout')
            | map('regex_search', 'exposure level for [^:]+: ([0-9.]+)', '\\1') | map('first') | map('float'))) }}
          tls_not_after: "{{ compliance_cert_end.stdout | default('') | regex_replace('^notAfter=', '') }}"
          tls_valid_30_days: "{{ (compliance_cert_30d.rc == 0) if compliance_cert_stat.stat.exists else none }}"
      vars:
        compliance_installed: "{{ compliance_packages | select('in', ansible_facts.packages) | list }}"
        compliance_sshd_lines: "{{ compliance_sshd.stdout_lines | select('match', '^(' ~ (compliance_sshd_keys | join('|')) ~ ') ') | list }}"

- name: Write the report
  hosts: localhost
  connection: local
  gather_facts: false
  become: false
  vars:
    compliance_dir: "{{ playbook_dir }}/reports"
    compliance_reported: "{{ groups['all'] | map('extract', hostvars) | selectattr('compliance_host', 'defined') | list }}"
    compliance_report:
      generated: "{{ now(utc=true).strftime('%Y-%m-%dT%H:%M:%SZ') }}"
      hosts: "{{ dict(compliance_reported | map(attribute='inventory_hostname') | zip(compliance_reported | map(attribute='compliance_host'))) }}"
  tasks:
    # assert compliance_reported is not empty; file: reports/ (0755)
    - name: Write reports/compliance.json
      ansible.builtin.copy:
        dest: "{{ compliance_dir }}/compliance.json"
        content: "{{ compliance_report | to_nice_json }}\n"
        mode: "0644"
    - name: Write reports/compliance.md
      ansible.builtin.template:
        src: compliance.md.j2
        dest: "{{ compliance_dir }}/compliance.md"
        mode: "0644"
```

`ansible/templates/compliance.md.j2`: a table per host (sshd values, unit scores, certificate
date, a verdict: sshd refuses root and passwords, `acme-hello` below 5.0, certificate valid for 30
days) and the package versions. `ansible/.gitignore`: `reports/`.

`.github/workflows/ansible.yml`: a second cron `"17 6 * * 1"`, `task` option `compliance`, the
drift job's `if` narrowed to `github.event.schedule == '41 5 * * 1-5'`, and:

```yaml
  compliance:
    if: ((github.event_name == 'schedule' && github.event.schedule == '17 6 * * 1') || (github.event_name == 'workflow_dispatch' && inputs.task == 'compliance')) && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: [self-hosted, acme-jump]
    # env as in apply
    steps:
      # checkout, ci-toolchain.sh
      - working-directory: ansible
        run: ansible-playbook compliance.yml --limit env_dev:env_hub -e @ci/runner.yml -e acme_kv_auth_source=msi
      - uses: actions/upload-artifact@v4
        with:
          name: compliance-report
          path: |
            ansible/reports/compliance.json
            ansible/reports/compliance.md
          if-no-files-found: error
          retention-days: 90
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
ansible-lint
ansible-playbook compliance.yml
jq '.hosts | map_values({root: .sshd.permitrootlogin, app: .units["acme-hello.service"], tls: .tls_not_after})' reports/compliance.json
less reports/compliance.md
# PR, merge, then:
gh workflow run ansible.yml -f task=compliance
gh run watch "$(gh run list --workflow ansible.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run download --name compliance-report --dir /tmp/report && ls /tmp/report
```

## Verify

`./lab.sh grade` runs `compliance.yml` on your machine (it only reads the hosts), checks the JSON,
and looks for the artifact `compliance-report` of a CI run.
