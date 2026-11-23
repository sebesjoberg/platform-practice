# tf-09 checks (sourced by the grader; cwd = LIVE_DIR)

# Code checks search every stack (and the modules repo): from tf-14 the spokes live in the
# env-dev / env-prod stacks, later in a module.
export TF09_PEER_RE='^[[:space:]]*resource[[:space:]]+"azurerm_virtual_network_peering"'
# Per directory: at most 2 peering resource blocks (one per direction, for_each over the
# environments); at least 2 in total.
export TF09_PEER_AWK='{ d = $1; sub(/\/[^\/]*$/, "", d); n[d] += $NF; t += $NF } END { for (d in n) if (n[d] > 2) exit 1; exit !(t >= 2) }'
tf09_tf_files() { # .tf files of the live repo's stacks, plus the modules repo once it exists
  local roots=(terraform)
  if [[ -n "${MODULES_DIR:-}" && -d "$MODULES_DIR" ]]; then roots+=("$MODULES_DIR"); fi
  find "${roots[@]}" -name "*.tf" -not -path "*/.terraform/*"
}
export TF09_RG_JQ='.location == env.LOCATION and .tags.env == $e and .tags.owner == env.OWNER_TAG and .tags.managed_by == "terraform"'
# sn(name; prefix; delegations) for spoke $e with second octet $x.
export TF09_SUBNETS_JQ='def sn($n; $p; $d): any(.[]; .name == $n and (.addressPrefix // .addressPrefixes[0]) == $p and ((.networkSecurityGroup.id // "") | ascii_downcase | endswith("/networksecuritygroups/nsg-\(env.PREFIX)-\($e)-" + ($n | ltrimstr("snet-")))) and ([.delegations[]?.serviceName] == $d)); sn("snet-app"; "10.\($x).1.0/24"; []) and sn("snet-pe"; "10.\($x).2.0/24"; []) and sn("snet-aca"; "10.\($x).4.0/23"; ["Microsoft.App/environments"])'
export TF09_PEER_JQ='any(.[]; .name == $n and .peeringState == "Connected" and ((.remoteVirtualNetwork.id // "") | ascii_downcase | endswith("/virtualnetworks/" + $r)))'
export -f tf09_tf_files

check_code "spoke peerings are declared once per direction (for_each, no copies)" \
  'tf09_tf_files | xargs -r grep -cE "$TF09_PEER_RE" /dev/null | awk -F: "$TF09_PEER_AWK"' \
  "declare two azurerm_virtual_network_peering resources (hub_to_spoke, spoke_to_hub), each with for_each over the environments; not one block per spoke"

check_code "a spoke subnet is delegated to Microsoft.App/environments" \
  'tf09_tf_files | xargs -r grep -lF "Microsoft.App/environments" /dev/null | grep -c . >/dev/null' \
  "snet-aca needs a delegation block with service_delegation name \"Microsoft.App/environments\""

check "rg-$PREFIX-dev and rg-$PREFIX-prod exist with the required tags" \
  'for e in dev prod; do az group show -n "rg-$PREFIX-$e" -o json | jq -e --arg e "$e" "$TF09_RG_JQ" >/dev/null || exit 1; done' \
  "expected rg-$PREFIX-dev / rg-$PREFIX-prod in $LOCATION with tags owner=$OWNER_TAG, env=dev/prod, managed_by=terraform"

check "spoke VNets have 10.1.0.0/16 (dev) and 10.2.0.0/16 (prod)" \
  'for x in 1:dev 2:prod; do e=${x#*:}; az network vnet show -g "rg-$PREFIX-$e" -n "vnet-$PREFIX-$e" -o json | jq -e --arg s "10.${x%%:*}.0.0/16" ".addressSpace.addressPrefixes == [\$s]" >/dev/null || exit 1; done' \
  "expected vnet-$PREFIX-dev 10.1.0.0/16 in rg-$PREFIX-dev and vnet-$PREFIX-prod 10.2.0.0/16 in rg-$PREFIX-prod"

check "spoke subnets have the right prefixes, NSGs and delegation" \
  'for x in 1:dev 2:prod; do e=${x#*:}; az network vnet subnet list -g "rg-$PREFIX-$e" --vnet-name "vnet-$PREFIX-$e" -o json | jq -e --arg e "$e" --arg x "${x%%:*}" "$TF09_SUBNETS_JQ" >/dev/null || exit 1; done' \
  "each spoke needs snet-app 10.x.1.0/24, snet-pe 10.x.2.0/24, snet-aca 10.x.4.0/23 (delegated to Microsoft.App/environments only), each with nsg-$PREFIX-<env>-<subnet>"

check "hub and spokes are peered in both directions (Connected)" \
  'for e in dev prod; do az network vnet peering list -g "rg-$PREFIX-hub" --vnet-name "vnet-$PREFIX-hub" -o json | jq -e --arg n "peer-hub-to-$e" --arg r "vnet-$PREFIX-$e" "$TF09_PEER_JQ" >/dev/null && az network vnet peering list -g "rg-$PREFIX-$e" --vnet-name "vnet-$PREFIX-$e" -o json | jq -e --arg n "peer-$e-to-hub" --arg r "vnet-$PREFIX-hub" "$TF09_PEER_JQ" >/dev/null || exit 1; done' \
  "expected peer-hub-to-<env> on vnet-$PREFIX-hub and peer-<env>-to-hub on vnet-$PREFIX-<env>, all Connected"
