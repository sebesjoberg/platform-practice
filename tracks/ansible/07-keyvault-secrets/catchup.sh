#!/usr/bin/env bash
# an-07 catchup (after-push, cwd = LIVE_DIR): the secret app-greeting in the dev vault, as in
# setup.sh. an-03's hook already created it before it applied the caught-up site.yml (it runs
# first), so this normally only confirms it. Idempotent; never overwrites a value.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_kv_secret_ensure
