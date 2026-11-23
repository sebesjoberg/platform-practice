#!/usr/bin/env bash
# an-14 catchup (after-push, cwd = LIVE_DIR): the release tag acme.platform-1.0.0 on GitHub,
# holding the collection of an-14's reference (lib/collection-tag.sh). an-01's hook already
# created every tag the caught-up tree pins before it installed the collections, so this is
# normally a no-op; it keeps 1.0.0 right when a later task's tree pins a newer release.
# Idempotent.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/collection-tag.sh"
an_collection_tag acme.platform-1.0.0
