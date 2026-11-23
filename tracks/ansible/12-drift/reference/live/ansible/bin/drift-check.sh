#!/usr/bin/env bash
# Drift check: does the fleet still match this repo? Runs site.yml in check mode with diffs, so
# nothing changes on the hosts, and every task that would change something is drift: a file
# edited by hand, a service stopped, a package removed.
#   bin/drift-check.sh [ansible-playbook options...]    e.g. --limit role_web, -e @ci/runner.yml
# Uses the ansible-playbook on PATH: activate ansible/.venv first (CI brings its own toolchain).
# Exit codes:
#   0  no drift: every host ok, changed=0
#   2  drift: at least one host would change (the diff above shows what)
#   1  the check itself failed: a failed or unreachable host, no hosts, or ansible-playbook failed
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

rc=0
ansible-playbook site.yml --check --diff "$@" 2>&1 | tee "$log" || rc=$?

# Read the PLAY RECAP (colour codes stripped: CI may force colours).
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
  echo "drift-check: the check failed (ansible-playbook exit $rc, $hosts host(s), $broken failed or unreachable)" >&2
  exit 1
fi
if [[ $drifted -gt 0 ]]; then
  echo "drift-check: DRIFT on $drifted of $hosts host(s): see the changed tasks and diffs above" >&2
  exit 2
fi
echo "drift-check: no drift on $hosts host(s)"
