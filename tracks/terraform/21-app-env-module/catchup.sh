#!/usr/bin/env bash
# tf-21 catchup (after-push): tag v2.1.0 at tf-21's reference modules tree and push it (a
# learner's own v2.1.0 is moved only after a warning; see lib/modules-tag.sh). tf-05's hook
# does this earlier when the tree pins v2.1.0 (its pipeline run needs the tag), and tf-04's hook
# has already applied bootstrap with the extended RBAC condition. Normally a no-op. Idempotent.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
modules_tag v2.1.0
