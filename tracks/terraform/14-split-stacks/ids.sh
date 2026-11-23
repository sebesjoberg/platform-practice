# shellcheck shell=bash
# tf-14 helpers, sourced by setup.sh and checks.sh: what moves from landing-zone into the env
# stacks, read with the same few bulk calls in both places (9 az calls in total).

TF14_ZONES="privatelink.vaultcore.azure.net privatelink.blob.core.windows.net"

# tf14_collect <ids-file> <guids-file>: writes the Azure IDs of everything that moves (per
# environment: resource group, VNet, subnets, NSGs, both peerings, the DNS zone links), sorted,
# in Azure's casing (usable in import blocks), and one "<vnet name> <resourceGuid>" line per
# spoke VNet. Returns 1 if any lookup failed; the files then hold what was found.
tf14_collect() {
  local ids=$1 guids=$2 rc=0 e rg vnet z j tmp
  tmp="$(mktemp)"
  : >"$guids"
  for e in dev prod; do
    rg="rg-$PREFIX-$e"
    vnet="vnet-$PREFIX-$e"
    az group show -n "$rg" --query id -o tsv >>"$tmp" || rc=1
    # the VNet, its subnets and its own (spoke -> hub) peering
    if j="$(az network vnet show -g "$rg" -n "$vnet" -o json)"; then
      jq -r '.id, (.subnets[]?.id), (.virtualNetworkPeerings[]?.id)' <<<"$j" >>"$tmp" || rc=1
      jq -r --arg v "$vnet" '"\($v) \(.resourceGuid)"' <<<"$j" >>"$guids" || rc=1
    else
      rc=1
    fi
    az network nsg list -g "$rg" --query "[].id" -o tsv >>"$tmp" || rc=1
  done
  az network vnet peering list -g "rg-$PREFIX-hub" --vnet-name "vnet-$PREFIX-hub" \
    --query "[?name=='peer-hub-to-dev' || name=='peer-hub-to-prod'].id" -o tsv >>"$tmp" || rc=1
  for z in $TF14_ZONES; do
    az network private-dns link vnet list -g "rg-$PREFIX-hub" -z "$z" \
      --query "[?name=='link-vnet-$PREFIX-dev' || name=='link-vnet-$PREFIX-prod'].id" -o tsv >>"$tmp" || rc=1
  done
  tr -d '\r' <"$tmp" | grep -v '^[[:space:]]*$' | sort -fu >"$ids"
  rm -f "$tmp"
  sort -o "$guids" "$guids"
  return "$rc"
}

# tf14_expected_ids: the same set built from the names (resource IDs derive from names). Used
# when setup.sh never took a snapshot, e.g. after ./lab.sh catchup.
tf14_expected_ids() {
  local s="/subscriptions/$SUBSCRIPTION_ID/resourceGroups" n="providers/Microsoft.Network" e z sn
  for e in dev prod; do
    echo "$s/rg-$PREFIX-$e"
    echo "$s/rg-$PREFIX-$e/$n/virtualNetworks/vnet-$PREFIX-$e"
    for sn in app pe aca; do
      echo "$s/rg-$PREFIX-$e/$n/virtualNetworks/vnet-$PREFIX-$e/subnets/snet-$sn"
      echo "$s/rg-$PREFIX-$e/$n/networkSecurityGroups/nsg-$PREFIX-$e-$sn"
    done
    echo "$s/rg-$PREFIX-$e/$n/virtualNetworks/vnet-$PREFIX-$e/virtualNetworkPeerings/peer-$e-to-hub"
    echo "$s/rg-$PREFIX-hub/$n/virtualNetworks/vnet-$PREFIX-hub/virtualNetworkPeerings/peer-hub-to-$e"
    for z in $TF14_ZONES; do
      echo "$s/rg-$PREFIX-hub/$n/privateDnsZones/$z/virtualNetworkLinks/link-vnet-$PREFIX-$e"
    done
  done
}
