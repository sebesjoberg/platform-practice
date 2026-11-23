#!/usr/bin/env bash
# Bring the self-hosted runner back after ./lab.sh pause / resume (from an-15 on). Resume rebuilds
# the jump host empty: the old runner shows offline in GitHub, and the Ansible pipeline (an-16)
# has nothing to run on. This script, run as you from your machine:
#   1. registers the new jump host with a fresh registration token (runner.yml; the token goes
#      through a 0600 file that is removed afterwards, --replace takes over the old name)
#   2. puts back the Key Vault objects the playbooks read (keyvault-prereqs.sh's step)
#   3. runs site.yml, which authorizes the runner's new SSH key on every VM
# Then queued or new ansible.yml runs work again.
#   tracks/ansible/lib/runner-register.sh
#
# Non-interactive, independent of the current directory. Config from the environment when
# PREFIX, SUFFIX, GH_OWNER, LIVE_REPO and LIVE_DIR are set, otherwise $LAB_HOME/config.env.
# Exit codes: 0 done (or nothing to do: no runner.yml yet), 1 a step failed, 3 a tool is missing.
set -euo pipefail
exec </dev/null

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"
# shellcheck source=/dev/null
source "$root/lib/common.sh"
if [[ -z "${PREFIX:-}" || -z "${SUFFIX:-}" || -z "${GH_OWNER:-}" || -z "${LIVE_REPO:-}" || -z "${LIVE_DIR:-}" ]]; then
  # shellcheck source=/dev/null
  source "$root/lib/config.sh"
  load_config
fi
export PREFIX SUFFIX GH_OWNER LIVE_REPO LIVE_DIR
# shellcheck source=/dev/null
source "$root/tracks/ansible/lib/ansible.sh"
need gh az python3

cd "$LIVE_DIR"
if [[ ! -f ansible/runner.yml ]]; then
  echo "runner-register: no ansible/runner.yml in $LIVE_DIR (an-15 not done yet); nothing to do"
  exit 0
fi

tok="$(mktemp)"
trap 'rm -f "$tok"' EXIT
chmod 600 "$tok"
gh api -X POST "repos/$GH_OWNER/$LIVE_REPO/actions/runners/registration-token" \
  --jq '{gh_runner_token: .token}' >"$tok" || {
  echo "runner-register: could not get a registration token (gh auth status?)" >&2
  exit 1
}
an_run ansible-playbook runner.yml -e "@$tok" || {
  echo "runner-register: runner.yml failed" >&2
  exit 1
}
rm -f "$tok"
an_kv_prereqs || {
  echo "runner-register: the Key Vault prerequisites failed (az login?)" >&2
  exit 1
}
an_run ansible-playbook site.yml || {
  echo "runner-register: site.yml failed" >&2
  exit 1
}
echo "runner-register: vm-$PREFIX-jump is the self-hosted runner again, its key authorized on the fleet"
