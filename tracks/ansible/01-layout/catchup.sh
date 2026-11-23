#!/usr/bin/env bash
# an-01 catchup (after-push, cwd = LIVE_DIR): build ansible/.venv from the pinned files now in the
# repo: requirements.txt, the collections (into ansible/collections) and the Azure collection's
# Python packages. Runs for every later an-* catchup too, so the venv always matches the tree it
# was caught up to (linters from an-04, Molecule from an-05). Idempotent; the first run downloads
# a few hundred MB (the Azure SDKs).
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
: "${LIVE_DIR:?LIVE_DIR not set; run ./lab.sh init}"
command -v python3 >/dev/null || { echo "an-01: python3 is required" >&2; exit 1; }
an_venv_sync
echo "an-01: ansible/.venv is in sync with ansible/requirements.txt and collections/requirements.yml"
