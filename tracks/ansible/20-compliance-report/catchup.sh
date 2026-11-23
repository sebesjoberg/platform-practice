#!/usr/bin/env bash
# an-20 catchup (after-push, cwd = LIVE_DIR), as you (gh): run the compliance job of ansible.yml
# on the self-hosted runner (dispatch task=compliance) and wait for it, so that the artifact
# compliance-report exists. Idempotent (each run uploads a new artifact; old ones expire).
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci.sh"
an_ci_dispatch_wait an-20 env=dev task=compliance
