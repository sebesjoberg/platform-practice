#!/usr/bin/env bash
# tf-14 setup (./lab.sh next): snapshot the Azure resource IDs of everything that moves from
# landing-zone into the env stacks (per environment: resource group, VNet, subnets, NSGs, both
# peerings, the DNS zone links) to $LAB_HOME/snapshots/tf-14.ids. The learner uses them for the
# import blocks; the grader checks every one still exists after the split. An existing snapshot
# is kept: the first one is the baseline. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
snap="$LAB_HOME/snapshots/tf-14.ids"
if [[ -s "$snap" ]]; then
  echo "tf-14: kept the existing snapshot $snap"
  exit 0
fi

hub="rg-$PREFIX-hub"
zones="privatelink.vaultcore.azure.net privatelink.blob.core.windows.net"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
missing=0
warn() { echo "tf-14: not found: $1" >&2; missing=1; }

for env in dev prod; do
  rg="rg-$PREFIX-$env" vnet="vnet-$PREFIX-$env"
  az group show -n "$rg" --query id -o tsv >>"$tmp" || warn "$rg"
  # the VNet, its subnets and its own (spoke -> hub) peering
  az network vnet show -g "$rg" -n "$vnet" -o json |
    jq -r '.id, (.subnets[]?.id), (.virtualNetworkPeerings[]?.id)' >>"$tmp" || warn "$vnet"
  az network nsg list -g "$rg" --query "[].id" -o tsv >>"$tmp" || warn "NSGs in $rg"
  az network vnet peering show -g "$hub" --vnet-name "vnet-$PREFIX-hub" -n "peer-hub-to-$env" \
    --query id -o tsv >>"$tmp" || warn "peer-hub-to-$env"
  for z in $zones; do
    az network private-dns link vnet show -g "$hub" -z "$z" -n "link-$vnet" --query id -o tsv >>"$tmp" ||
      warn "link-$vnet in $z"
  done
done

mkdir -p "$(dirname "$snap")"
tr -d '\r' <"$tmp" | grep -v '^[[:space:]]*$' | sort -fu >"$snap"
echo "tf-14: saved $(wc -l <"$snap" | tr -d ' ') resource IDs to $snap (the IDs for your import blocks)"
if [[ $missing -ne 0 ]]; then
  echo "tf-14: some spoke resources are missing; finish tf-09/tf-10 (or ./lab.sh catchup tf-13), then delete $snap and run ./lab.sh next again" >&2
fi
