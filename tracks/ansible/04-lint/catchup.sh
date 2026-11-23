#!/usr/bin/env bash
# an-04 catchup (after-push, cwd = LIVE_DIR): install the pre-commit git hook from the config in
# the repo (a local, non-file step). Idempotent.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
cfg="$(an_precommit_config)" || { echo "an-04: no pre-commit config in the repo" >&2; exit 1; }
ansible/.venv/bin/pre-commit install --config "$cfg"
echo "an-04: pre-commit hook installed ($cfg)"
