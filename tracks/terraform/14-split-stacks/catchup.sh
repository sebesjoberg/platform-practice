#!/usr/bin/env bash
# tf-14 catchup (after-push): the reference has no import blocks, so catching up from a tf-13
# state destroys and recreates the spokes (same names, same IDs, new resourceGuids). That is a
# legitimate rebuild, not a botched move: drop the VNet guid baseline so the recreate check
# doesn't fail. The ID snapshot stays (IDs derive from names). Idempotent.
set -euo pipefail

rm -f "${LAB_HOME:-$HOME/.platform-lab}/snapshots/tf-14.guids"
echo "tf-14: VNet resourceGuid baseline cleared (catchup rebuilds the spokes)"
