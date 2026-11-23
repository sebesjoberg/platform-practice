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
# Shared with tf-15: tracks/terraform/lib/spoke-ids.sh.
# shellcheck source=/dev/null
source "$here/../lib/spoke-ids.sh"

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
rc=0
spoke_snapshot tf-14 || rc=$?
echo "tf-14: the IDs in $LAB_HOME/snapshots/tf-14.ids are the ones your import blocks need"
if [[ $rc -ne 0 ]]; then
  echo "tf-14: some spoke resources are missing; finish tf-09/tf-10 (or ./lab.sh catchup tf-13), then delete $LAB_HOME/snapshots/tf-14.ids and run ./lab.sh next again" >&2
fi
