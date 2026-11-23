#!/usr/bin/env bash
# an-03 catchup (after-push, cwd = LIVE_DIR): apply site.yml to the VMs once, so they carry the
# baseline and everything else the caught-up tree configures (the web stack from an-06, HAProxy
# from an-10). an-01's hook (earlier in the same catchup) built the venv. Later tasks' Key Vault
# prerequisites (an-07's secret, an-08's certificate) are created first, because their own hooks
# run after this one. Idempotent: a second run changes nothing.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_catchup_converge
echo "an-03: site.yml applied"
