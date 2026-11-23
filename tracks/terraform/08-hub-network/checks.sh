# tf-08 checks (sourced by the grader; cwd = LIVE_DIR)

export TF08_RG="rg-$PREFIX-hub" TF08_VNET="vnet-$PREFIX-hub"
export TF08_SPACE_JQ='.addressSpace.addressPrefixes == ["10.0.0.0/16"]'
# sn(name; prefix; nsg): the subnet exists with that prefix and that NSG associated.
export TF08_SUBNETS_JQ='def sn($n; $p; $g): any(.[]; .name == $n and (.addressPrefix // .addressPrefixes[0]) == $p and ((.networkSecurityGroup.id // "") | ascii_downcase | endswith("/networksecuritygroups/" + $g))); sn("snet-shared"; "10.0.1.0/24"; "nsg-\(env.PREFIX)-hub-shared") and sn("snet-runner"; "10.0.2.0/24"; "nsg-\(env.PREFIX)-hub-runner") and sn("snet-pe"; "10.0.3.0/24"; "nsg-\(env.PREFIX)-hub-pe")'
export TF08_NSG_TAGS_JQ='[.[] | select(.name | test("^nsg-" + env.PREFIX + "-hub-(shared|runner|pe)$"))] | length == 3 and all(.[]; .location == env.LOCATION and .tags.env == "hub" and .tags.owner == env.OWNER_TAG)'

check_code "hub VNet and subnets are declared in landing-zone" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_virtual_network\"" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_subnet\"" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone needs an azurerm_virtual_network and azurerm_subnet resources"

check_code "NSGs and subnet associations are declared in landing-zone" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_network_security_group\"" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_subnet_network_security_group_association\"" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone needs azurerm_network_security_group and azurerm_subnet_network_security_group_association resources"

check "$TF08_VNET has address space 10.0.0.0/16" \
  'az network vnet show -g "$TF08_RG" -n "$TF08_VNET" -o json | jq -e "$TF08_SPACE_JQ"' \
  "expected $TF08_VNET in $TF08_RG with exactly 10.0.0.0/16"

check "hub subnets have the right prefixes and NSGs" \
  'az network vnet subnet list -g "$TF08_RG" --vnet-name "$TF08_VNET" -o json | jq -e "$TF08_SUBNETS_JQ"' \
  "expected snet-shared 10.0.1.0/24, snet-runner 10.0.2.0/24, snet-pe 10.0.3.0/24, each associated with nsg-$PREFIX-hub-<subnet>"

check "hub NSGs are in $LOCATION with the hub tags" \
  'az network nsg list -g "$TF08_RG" -o json | jq -e "$TF08_NSG_TAGS_JQ"' \
  "expected nsg-$PREFIX-hub-shared, -runner and -pe in $TF08_RG ($LOCATION) with tags env=hub, owner=$OWNER_TAG"
