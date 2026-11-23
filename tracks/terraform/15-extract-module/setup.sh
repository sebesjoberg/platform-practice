#!/usr/bin/env bash
# tf-15 setup (./lab.sh next): snapshot every spoke resource before it moves into the module.
#   $LAB_HOME/snapshots/tf-15.ids    Azure IDs (per environment: resource group, VNet, subnets,
#                                    NSGs, both peerings, DNS zone links); the grader checks they
#                                    all still exist
#   $LAB_HOME/snapshots/tf-15.guids  resourceGuid of each spoke VNet; changes only if the VNet
#                                    was destroyed and recreated (tf-15's catchup deletes it)
# An existing snapshot is kept: the first one is the baseline. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shared with tf-14: tracks/terraform/lib/spoke-ids.sh.
# shellcheck source=/dev/null
source "$here/../lib/spoke-ids.sh"

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
if ! spoke_snapshot tf-15; then
  echo "tf-15: some spoke resources are missing; finish tf-14 (or ./lab.sh catchup tf-14), then delete $LAB_HOME/snapshots/tf-15.ids and run ./lab.sh next again" >&2
fi
