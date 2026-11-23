#!/usr/bin/env bash
# tf-15 catchup (after-push): the reference's moved blocks keep the spokes when catchup starts
# from the tf-14 reference, but catchup may start from any state (the learner's own addresses,
# or no spokes at all), and then the pipeline rebuilds them with new resourceGuids. That is a
# legitimate rebuild, not a botched extraction: drop the VNet guid baseline so the recreate check
# doesn't fail. The ID snapshot stays (IDs derive from names). Idempotent.
set -euo pipefail

rm -f "${LAB_HOME:-$HOME/.platform-lab}/snapshots/tf-15.guids"
echo "tf-15: VNet resourceGuid baseline cleared (catchup may rebuild the spokes)"
