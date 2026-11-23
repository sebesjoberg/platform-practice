#!/usr/bin/env bash
# an-08 catchup (after-push, cwd = LIVE_DIR): your Certificates Officer role on the dev vault and
# the certificate web-tls, as in setup.sh. an-03's hook already created them before it applied
# the caught-up site.yml (it runs first), so this normally only confirms them. Idempotent.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_kv_cert_ensure
