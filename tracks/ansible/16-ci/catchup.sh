#!/usr/bin/env bash
# an-16 catchup (after-push, cwd = LIVE_DIR), as you (gh): the Ansible pipeline on the
# self-hosted runner (registered by an-15's hook, earlier in this catchup). Dispatches ansible.yml
# twice and waits for each run: task=apply (job apply on the runner) and task=drift (the drift
# check, which must find nothing right after the apply). Catchup opens no pull request; the
# grader accepts its own green push to main instead of a pull request run. Idempotent.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci.sh"
an_ci_dispatch_wait an-16 env=dev task=apply
an_ci_dispatch_wait an-16 env=dev task=drift
