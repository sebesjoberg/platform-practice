#!/usr/bin/env bash
# an-03 catchup (after-push, cwd = LIVE_DIR): apply site.yml to the VMs once, so they carry the
# baseline the later tasks build on. an-01's hook (earlier in the same catchup) built the venv.
# Idempotent: a second run changes nothing.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_run ansible-playbook site.yml
echo "an-03: site.yml applied"
