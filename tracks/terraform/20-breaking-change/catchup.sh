#!/usr/bin/env bash
# tf-20 catchup (after-push): tag v2.0.0 at tf-20's reference module and push it. tf-05's hook
# does this earlier when the tree pins v2 (its pipeline run needs the tag), so here it is
# normally a no-op. Idempotent.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
modules_tag v2.0.0 tf-20
