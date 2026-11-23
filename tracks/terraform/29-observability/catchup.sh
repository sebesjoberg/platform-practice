#!/usr/bin/env bash
# tf-29 catchup (after-push): the reference has no import or removed blocks, so catching up from a
# tf-28 state destroys the workspace in landing-zone and creates it again in observability (same
# name and resource ID; Azure may hand out a new customerId). That is a legitimate rebuild, not a
# botched move: drop the customerId baseline so the recreate check doesn't fail. The ID snapshot
# stays (resource IDs derive from names). Idempotent.
set -euo pipefail

rm -f "${LAB_HOME:-$HOME/.platform-lab}/snapshots/tf-29.guids"
echo "tf-29: workspace customerId baseline cleared (catchup rebuilds the workspace)"
