# tf-14 checks (sourced by the grader; cwd = LIVE_DIR)

export TF14_SA="st${PREFIX}tfstate$SUFFIX"
export TF14_SNAP="$LAB_HOME/snapshots/tf-14.ids"
export TF14_IMPORT_RE='^[[:space:]]*import[[:space:]]*\{'
export TF14_VNETS_JQ='[.resources[]? | select(.mode == "managed" and .type == "azurerm_virtual_network") | .instances[].attributes.name] == [$v]'

tf14_has_key() { # tf14_has_key <stack> <key>
  grep -rqsE "backend[[:space:]]+\"azurerm\"" "terraform/$1" --include="*.tf" &&
    grep -rqsE "key[[:space:]]*=[[:space:]]*\"$2\"" "terraform/$1" --include="*.tf"
}
# tf14_expected_ids: what moves, built from the names (when setup.sh never took a snapshot,
# e.g. after ./lab.sh catchup). Resource IDs are derived from names.
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
    for z in privatelink.vaultcore.azure.net privatelink.blob.core.windows.net; do
      echo "$s/rg-$PREFIX-hub/$n/privateDnsZones/$z/virtualNetworkLinks/link-vnet-$PREFIX-$e"
    done
  done
}
# tf14_ids_unchanged: every snapshotted ID still resolves to the same resource ID in Azure.
tf14_ids_unchanged() {
  local want got
  if [[ -s "$TF14_SNAP" ]]; then want="$(tr -d '\r' <"$TF14_SNAP")"; else want="$(tf14_expected_ids)"; fi
  want="$(tr '[:upper:]' '[:lower:]' <<<"$want" | grep -v '^[[:space:]]*$' | sort -u)"
  [[ -n "$want" ]] || return 1
  # shellcheck disable=SC2086 # one argument per ID
  got="$(az resource show --ids $want -o json | jq -r 'if type == "array" then .[].id else .id end' |
    tr '[:upper:]' '[:lower:]' | sort -u)" || return 1
  [[ -z "$(comm -23 <(echo "$want") <(echo "$got"))" ]]
}
# tf14_state_vnets <key> <vnet>: the state blob <key> manages exactly the VNet <vnet>.
tf14_state_vnets() {
  local f rc=0
  f="$(mktemp)"
  az storage blob download --auth-mode login --account-name "$TF14_SA" -c tfstate -n "$1" -f "$f" --no-progress -o none &&
    jq -e --arg v "$2" "$TF14_VNETS_JQ" "$f" >/dev/null || rc=1
  rm -f "$f"
  return "$rc"
}
export -f tf14_has_key tf14_expected_ids tf14_ids_unchanged tf14_state_vnets

check_code "env-dev and env-prod have their own state keys" \
  'tf14_has_key env-dev env-dev\\.tfstate && tf14_has_key env-prod env-prod\\.tfstate && tf14_has_key landing-zone landing-zone\\.tfstate' \
  "terraform/env-dev and terraform/env-prod need backend \"azurerm\" with key env-dev.tfstate / env-prod.tfstate (landing-zone keeps landing-zone.tfstate)"

check_code "env stacks read the hub with data sources, not terraform_remote_state" \
  '[[ -d terraform/env-dev && -d terraform/env-prod ]] && for s in env-dev env-prod; do grep -rqsE "data[[:space:]]+\"azurerm_virtual_network\"" "terraform/$s" --include="*.tf" || exit 1; done && ! grep -rqsE "terraform_remote_state" terraform/env-* --include="*.tf"' \
  "terraform/env-dev and terraform/env-prod must find vnet-$PREFIX-hub with data \"azurerm_virtual_network\", and never use terraform_remote_state"

check_code "landing-zone no longer declares the spokes" \
  '[[ -d terraform/landing-zone ]] && ! grep -rqsE "resource[[:space:]]+\"azurerm_virtual_network_peering\"" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone still declares peerings: the spokes (and both peering directions) belong to the env stacks now"

check_code "the move is finished: no import blocks left in the env stacks" \
  '[[ -d terraform/env-dev && -d terraform/env-prod ]] && ! grep -rqsE "$TF14_IMPORT_RE" terraform/env-dev terraform/env-prod --include="*.tf"' \
  "delete the import blocks once the move is applied (PR 2): an import of a missing object fails, which breaks ./lab.sh resume after a pause"

check "state blobs landing-zone.tfstate, env-dev.tfstate and env-prod.tfstate exist" \
  'for k in landing-zone env-dev env-prod; do [[ "$(az storage blob exists --auth-mode login --account-name "$TF14_SA" -c tfstate -n "$k.tfstate" --query exists -o tsv)" == true ]] || exit 1; done' \
  "expected the blobs landing-zone.tfstate, env-dev.tfstate and env-prod.tfstate in $TF14_SA/tfstate (has the pipeline applied the env stacks?)"

check "each state manages its own VNet (landing-zone only the hub)" \
  'tf14_state_vnets landing-zone.tfstate "vnet-$PREFIX-hub" && tf14_state_vnets env-dev.tfstate "vnet-$PREFIX-dev" && tf14_state_vnets env-prod.tfstate "vnet-$PREFIX-prod"' \
  "landing-zone.tfstate must hold only vnet-$PREFIX-hub, env-dev.tfstate only vnet-$PREFIX-dev, env-prod.tfstate only vnet-$PREFIX-prod"

check "every moved resource still exists with the same ID" \
  'tf14_ids_unchanged' \
  "a resource from $TF14_SNAP (or the expected spoke resources) no longer exists under its ID: was something destroyed or renamed?"
