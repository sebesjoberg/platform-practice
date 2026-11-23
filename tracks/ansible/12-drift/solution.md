# an-12 solution

## Approach

Drift detection is `site.yml` in check mode with diffs: the roles already describe every host
completely, so any task that would change something is drift. A small script turns the recap into
an exit code that a person and a scheduler can both act on. Check mode exposed one task that
can't be simulated (the `uri` health wait), which now skips itself in check mode.

## Code

`ansible/bin/drift-check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

rc=0
ansible-playbook site.yml --check --diff "$@" 2>&1 | tee "$log" || rc=$?

read -r hosts drifted broken < <(awk '
  { gsub(/\033\[[0-9;]*m/, "") }
  /^PLAY RECAP/ { on = 1; next }
  on && / : ok=[0-9]+/ {
    hosts++
    if (match($0, /changed=[0-9]+/) && substr($0, RSTART + 8, RLENGTH - 8) + 0 > 0) drifted++
    if ($0 ~ /unreachable=[1-9]/ || $0 ~ /failed=[1-9]/) broken++
  }
  END { printf "%d %d %d\n", hosts, drifted, broken }
' "$log")

if [[ $rc -ne 0 || $hosts -eq 0 || $broken -gt 0 ]]; then
  echo "drift-check: the check failed (exit $rc, $hosts host(s), $broken failed or unreachable)" >&2
  exit 1
fi
if [[ $drifted -gt 0 ]]; then
  echo "drift-check: DRIFT on $drifted of $hosts host(s): see the diffs above" >&2
  exit 2
fi
echo "drift-check: no drift on $hosts host(s)"
```

`roles/acme_hello/tasks/main.yml`, the health wait:

```yaml
- name: Wait until the app reports healthy with this release
  ansible.builtin.uri:
    url: "http://127.0.0.1:{{ acme_hello_port }}/health"
    return_content: true
  register: acme_hello_health
  until: acme_hello_health.status == 200 and (acme_hello_health.content | trim) == 'ok ' ~ acme_hello_version
  retries: "{{ acme_hello_health_retries }}"
  delay: 2
  changed_when: false
  when: not ansible_check_mode
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
chmod +x bin/drift-check.sh
bin/drift-check.sh; echo "exit $?"
#   TASK [nginx : Write the nginx configuration]
#   --- before: /etc/nginx/nginx.conf
#   -    worker_connections 1;
#   +    worker_connections 768;
#   changed: [vm-{{PREFIX}}-web-dev-2]
#   TASK [nginx : Keep nginx running and enabled]  changed: [vm-{{PREFIX}}-web-dev-2]
#   exit 2

ansible-playbook site.yml          # remediate: the role's template and service state win
bin/drift-check.sh; echo "exit $?" # exit 0
ansible role_jump -b -m ansible.builtin.shell -a 'echo "show servers state web" | socat stdio /run/haproxy/admin.sock'
```

Commit the script and the role change on a branch, pull request, merge. an-16 runs the script on
a schedule in CI and files an issue when it exits 2.

## Verify

`./lab.sh grade`: the script against a stand-in `ansible-playbook` (clean, drift, unreachable),
the web page on both VMs, and a real `bin/drift-check.sh` run that must exit 0.
