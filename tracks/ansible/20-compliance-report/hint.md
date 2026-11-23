# an-20 hints

Docs:
- `ansible.builtin.package_facts` and `service_facts`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_facts_module.html
- `hostvars`, `groups` and building data on the control node: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#information-about-ansible-magic-variables
- `actions/upload-artifact`: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/storing-and-sharing-data-from-a-workflow
- Several schedules in one workflow (`github.event.schedule`): https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule

Traps:
- **Effective, not configured:** `sshd -T` (as root) prints what sshd really uses, drop-ins and
  `Match` defaults included, all keys in lowercase. Grepping `sshd_config` answers a different
  question.
- **Read-only means `changed_when: false`** on every `command`, so a run reports `changed=0` and
  could even run in check mode. Commands don't run in check mode unless you say so.
- **Collect per host, write once:** each host builds a fact (`set_fact`), then a play on
  `localhost` (`connection: local`, `become: false`) reads them from `hostvars` and writes the
  files. With `--limit`, only the hosts that ran have the fact: filter with
  `selectattr('compliance_host', 'defined')` instead of assuming all of `groups['all']`.
- **CI passes `-e @ci/runner.yml`**, and extra variables apply to `localhost` as well. Every
  connection variable in it must template for a host without Azure host variables
  (`private_ipv4_addresses | default([inventory_hostname]) | first`), or the localhost play fails
  with "'private_ipv4_addresses' is undefined" in CI only.
- **`systemd-analyze security <unit>`** ends with `Overall exposure level for <unit>: 1.9 OK`;
  `regex_search('exposure level for [^:]+: ([0-9.]+)', '\1')` returns a list. The distribution's
  own units (nginx, haproxy) score high; report them, judge only what you hardened.
- **Certificates:** `openssl x509 -enddate -noout -in <file>` prints `notAfter=...`;
  `-checkend 2592000` exits 1 when it expires within 30 days (that's not an error: allow rc 1).
- **`strategy: free`** fits a play where every host works alone (an-17); the report play runs
  after it in any case, because plays never overlap.
- **Two crons, two jobs:** `on.schedule` takes a list; `github.event.schedule` tells the job
  which cron fired, so the weekly report doesn't run the drift check and vice versa.
- **`if-no-files-found: error`** on the upload step makes a run without a report red instead of
  green with nothing in it.
