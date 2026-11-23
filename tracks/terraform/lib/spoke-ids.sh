# shellcheck shell=bash
# Spoke resource snapshots, shared by tf-14 (split into env stacks) and tf-15 (extract the spoke
# module): both move every spoke resource to a new address and must not destroy any of them.
# Sourced by their setup.sh and checks.sh. Needs the config (PREFIX, SUBSCRIPTION_ID, ...) and
# LAB_HOME. The lookups are the same few bulk calls everywhere (9 az calls in total).

SPOKE_ZONES="privatelink.vaultcore.azure.net privatelink.blob.core.windows.net"

# spoke_collect <ids-file> <guids-file>: writes the Azure IDs of every spoke resource (per
# environment: resource group, VNet, subnets, NSGs, both peerings, the DNS zone links), sorted,
# in Azure's casing (usable in import blocks), and one "<vnet name> <resourceGuid>" line per
# spoke VNet. Returns 1 if any lookup failed; the files then hold what was found.
spoke_collect() {
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
  for z in $SPOKE_ZONES; do
    az network private-dns link vnet list -g "rg-$PREFIX-hub" -z "$z" \
      --query "[?name=='link-vnet-$PREFIX-dev' || name=='link-vnet-$PREFIX-prod'].id" -o tsv >>"$tmp" || rc=1
  done
  tr -d '\r' <"$tmp" | grep -v '^[[:space:]]*$' | sort -fu >"$ids"
  rm -f "$tmp"
  sort -o "$guids" "$guids"
  return "$rc"
}

# spoke_expected_ids: the same set built from the names (resource IDs derive from names). Used
# when setup.sh never took a snapshot, e.g. after ./lab.sh catchup.
spoke_expected_ids() {
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
    for z in $SPOKE_ZONES; do
      echo "$s/rg-$PREFIX-hub/$n/privateDnsZones/$z/virtualNetworkLinks/link-vnet-$PREFIX-$e"
    done
  done
}

# spoke_snapshot <task-id>: setup.sh body. Writes $LAB_HOME/snapshots/<id>.ids and <id>.guids
# unless the .ids file exists (the first snapshot is the baseline). Prints what it did; returns 1
# when some spoke resources were missing (the files then hold what was found).
spoke_snapshot() {
  local id=$1 snap guids rc=0
  snap="$LAB_HOME/snapshots/$id.ids"
  guids="$LAB_HOME/snapshots/$id.guids"
  if [[ -s "$snap" ]]; then
    echo "$id: kept the existing snapshot $snap"
    return 0
  fi
  mkdir -p "$(dirname "$snap")"
  spoke_collect "$snap.tmp" "$guids.tmp" || rc=1
  mv "$snap.tmp" "$snap"
  mv "$guids.tmp" "$guids"
  echo "$id: saved $(wc -l <"$snap" | tr -d ' ') resource IDs to $snap and each spoke VNet's resourceGuid to $guids"
  return "$rc"
}

# spoke_ids_unchanged <snapshot>: every ID of the snapshot (or, without one, of the name-derived
# list) still exists. Compared case-insensitively against the same bulk lookups setup.sh used.
spoke_ids_unchanged() {
  local snap=$1 d want rc=0
  d="$(mktemp -d)"
  if [[ -s "$snap" ]]; then want="$(cat "$snap")"; else want="$(spoke_expected_ids)"; fi
  tr -d '\r' <<<"$want" | tr '[:upper:]' '[:lower:]' | grep -v '^[[:space:]]*$' | sort -u >"$d/want"
  spoke_collect "$d/ids" "$d/guids" || true
  tr '[:upper:]' '[:lower:]' <"$d/ids" | sort -u >"$d/got"
  [[ -s "$d/want" && -z "$(comm -23 "$d/want" "$d/got")" ]] || rc=1
  rm -rf "$d"
  return "$rc"
}

# spoke_guids_unchanged <guids-file>: each spoke VNet keeps the resourceGuid setup.sh recorded
# (it changes only when a VNet is destroyed and recreated). No baseline (catchup removed it, or
# setup.sh never ran) means nothing to compare.
spoke_guids_unchanged() {
  local base=$1 d rc=0
  [[ -s "$base" ]] || return 0
  d="$(mktemp -d)"
  spoke_collect "$d/ids" "$d/guids" || true
  [[ -z "$(comm -23 <(sort "$base") "$d/guids")" ]] || rc=1
  rm -rf "$d"
  return "$rc"
}

# spoke_state_jq <state key> <jq filter> [jq args...]: downloads the state blob from the state
# account and evaluates the filter with jq -e (true = pass).
spoke_state_jq() {
  local key=$1 f rc=0
  shift
  f="$(mktemp)"
  az storage blob download --auth-mode login --account-name "st${PREFIX}tfstate$SUFFIX" -c tfstate \
    -n "$key" -f "$f" --no-progress -o none &&
    jq -e "$@" "$f" >/dev/null || rc=1
  rm -f "$f"
  return "$rc"
}
