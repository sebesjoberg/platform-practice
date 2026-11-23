#!/usr/bin/env bash
# tf-29 setup (./lab.sh next): snapshot what moves from landing-zone to observability.
#   $LAB_HOME/snapshots/tf-29.ids    the workspace's resource ID and the diagnostic setting's import
#                                    ID (<subscription id>|activity-log-to-law), in Azure's casing:
#                                    what the import blocks need
#   $LAB_HOME/snapshots/tf-29.guids  the workspace's customerId (workspace ID); it only changes when
#                                    the workspace is destroyed and created again (tf-29's catchup
#                                    deletes this baseline)
# An existing snapshot is kept: the first one is the baseline. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID not set; run ./lab.sh init}"
snap="$LAB_HOME/snapshots/tf-29.ids"
guids="$LAB_HOME/snapshots/tf-29.guids"

if [[ -s "$snap" ]]; then
  echo "tf-29: kept the existing snapshot $snap"
else
  mkdir -p "$(dirname "$snap")"
  if ! j="$(az monitor log-analytics workspace show -g "rg-$PREFIX-hub" -n "law-$PREFIX-platform" -o json)"; then
    echo "tf-29: law-$PREFIX-platform not found; finish tf-13 (or ./lab.sh catchup tf-28), then run ./lab.sh next again" >&2
    exit 1
  fi
  {
    jq -r '.id' <<<"$j"
    echo "/subscriptions/$SUBSCRIPTION_ID|activity-log-to-law"
  } >"$snap"
  jq -r '"law-\(env.PREFIX)-platform \(.customerId)"' <<<"$j" >"$guids"
  echo "tf-29: saved the import IDs to $snap and the workspace's customerId to $guids"
fi
