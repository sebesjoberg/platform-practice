#!/usr/bin/env bash
# tf-14 setup (./lab.sh next): snapshot what moves from landing-zone into the env stacks.
#   $LAB_HOME/snapshots/tf-14.ids    Azure IDs (per environment: resource group, VNet, subnets,
#                                    NSGs, both peerings, DNS zone links); the learner uses them
#                                    in the import blocks, the grader checks they still exist
#   $LAB_HOME/snapshots/tf-14.guids  resourceGuid of each spoke VNet; changes only if the VNet
#                                    was destroyed and recreated (tf-14's catchup deletes it)
# An existing snapshot is kept: the first one is the baseline. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ids.sh lives next to this script.
# shellcheck source=/dev/null
source "$here/ids.sh"

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
snap="$LAB_HOME/snapshots/tf-14.ids"
guids="$LAB_HOME/snapshots/tf-14.guids"
if [[ -s "$snap" ]]; then
  echo "tf-14: kept the existing snapshot $snap"
  exit 0
fi

mkdir -p "$(dirname "$snap")"
rc=0
tf14_collect "$snap.tmp" "$guids.tmp" || rc=$?
mv "$snap.tmp" "$snap"
mv "$guids.tmp" "$guids"
echo "tf-14: saved $(wc -l <"$snap" | tr -d ' ') resource IDs to $snap (the IDs for your import blocks)"
if [[ $rc -ne 0 ]]; then
  echo "tf-14: some spoke resources are missing; finish tf-09/tf-10 (or ./lab.sh catchup tf-13), then delete $snap and run ./lab.sh next again" >&2
fi
