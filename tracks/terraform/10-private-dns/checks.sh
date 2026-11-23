# tf-10 checks (sourced by the grader; cwd = LIVE_DIR)

export TF10_RG="rg-$PREFIX-hub"
export TF10_VNET_BASE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX"
# The zone has (at least) the links link-vnet-{P}-{hub,dev,prod}, each to its VNet, registration off.
export TF10_LINKS_JQ='def want($v): {name: ("link-vnet-" + env.PREFIX + "-" + $v), vnet: ((env.TF10_VNET_BASE + "-" + $v + "/providers/Microsoft.Network/virtualNetworks/vnet-" + env.PREFIX + "-" + $v) | ascii_downcase), reg: false}; ([want("hub"), want("dev"), want("prod")] - [.[] | {name, vnet: (.virtualNetwork.id | ascii_downcase), reg: .registrationEnabled}]) == []'

check_code "landing-zone declares both private DNS zones" \
  'grep -rqsE "resource[[:space:]]+\"azurerm_private_dns_zone\"" terraform/landing-zone --include="*.tf" && grep -rqsF "privatelink.vaultcore.azure.net" terraform/landing-zone --include="*.tf" && grep -rqsF "privatelink.blob.core.windows.net" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone needs azurerm_private_dns_zone for privatelink.vaultcore.azure.net and privatelink.blob.core.windows.net"

check_code "private DNS zone VNet links are declared" \
  'grep -rqsE "resource[[:space:]]+\"azurerm_private_dns_zone_virtual_network_link\"" terraform --include="*.tf"' \
  "no azurerm_private_dns_zone_virtual_network_link under terraform/"

check "both private DNS zones exist in $TF10_RG" \
  'for z in privatelink.vaultcore.azure.net privatelink.blob.core.windows.net; do az network private-dns zone show -g "$TF10_RG" -n "$z" --query id -o tsv >/dev/null || exit 1; done' \
  "expected private DNS zones privatelink.vaultcore.azure.net and privatelink.blob.core.windows.net in $TF10_RG"

check "privatelink.vaultcore.azure.net is linked to the hub, dev and prod VNets" \
  'az network private-dns link vnet list -g "$TF10_RG" -z privatelink.vaultcore.azure.net -o json | jq -e "$TF10_LINKS_JQ"' \
  "expected link-vnet-$PREFIX-hub, link-vnet-$PREFIX-dev and link-vnet-$PREFIX-prod, each to its VNet, registrationEnabled false"

check "privatelink.blob.core.windows.net is linked to the hub, dev and prod VNets" \
  'az network private-dns link vnet list -g "$TF10_RG" -z privatelink.blob.core.windows.net -o json | jq -e "$TF10_LINKS_JQ"' \
  "expected link-vnet-$PREFIX-hub, link-vnet-$PREFIX-dev and link-vnet-$PREFIX-prod, each to its VNet, registrationEnabled false"
