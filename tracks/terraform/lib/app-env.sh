# shellcheck shell=bash
# Checks of one environment's app-env resources (tf-21 for dev, tf-24 for prod), and of role
# assignments in general (tf-22, tf-25). Sourced by checks.sh, which exports what its commands
# use with export -f. Needs the config (PREFIX, SUFFIX, SUBSCRIPTION_ID) and az + jq.

# appenv_kv_name <env>: kv-<prefix>-<env>-<suffix>
appenv_kv_name() { echo "kv-$PREFIX-$1-$SUFFIX"; }

# appenv_kv_id <env>: the vault's resource ID, from its name.
appenv_kv_id() {
  echo "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-$1/providers/Microsoft.KeyVault/vaults/$(appenv_kv_name "$1")"
}

# appenv_kv_ok <env>: the vault is in rg-<prefix>-<env> with RBAC, 7 days of soft delete, no
# purge protection and public network access enabled.
appenv_kv_ok() {
  az keyvault show -g "rg-$PREFIX-$1" -n "$(appenv_kv_name "$1")" -o json |
    jq -e '.properties as $p | $p.enableRbacAuthorization == true and $p.softDeleteRetentionInDays == 7
      and ($p.enablePurgeProtection // false) == false and ($p.publicNetworkAccess // "Enabled") == "Enabled"' >/dev/null
}

# appenv_pe_ok <env>: pe-kv-<prefix>-<env> sits in vnet-<prefix>-<env>/snet-pe, connects to the
# vault's "vault" sub-resource (approved), and has a DNS zone group with privatelink.vaultcore.
appenv_pe_ok() {
  local rg="rg-$PREFIX-$1" pe="pe-kv-$PREFIX-$1" kv
  kv="$(appenv_kv_id "$1")"
  az network private-endpoint show -g "$rg" -n "$pe" -o json |
    jq -e --arg v "vnet-$PREFIX-$1" --arg kv "$kv" '
      (.subnet.id | ascii_downcase | endswith("/virtualnetworks/\($v)/subnets/snet-pe"))
      and any(.privateLinkServiceConnections[]?; (.privateLinkServiceId | ascii_downcase) == ($kv | ascii_downcase)
        and .groupIds == ["vault"] and .privateLinkServiceConnectionState.status == "Approved")' >/dev/null &&
    az network private-endpoint dns-zone-group list -g "$rg" --endpoint-name "$pe" -o json |
    jq -e 'any(.[]?.privateDnsZoneConfigs[]?; (.privateDnsZoneId | ascii_downcase | endswith("/privatednszones/privatelink.vaultcore.azure.net")))' >/dev/null
}

# appenv_identity_pid <env>: principal ID of id-<prefix>-app-<env>.
appenv_identity_pid() { az identity show -g "rg-$PREFIX-$1" -n "id-$PREFIX-app-$1" --query principalId -o tsv; }

# role_on <principal id> <scope> <role name>: the principal holds <role name> at exactly <scope>
# (scopes compared case-insensitively).
role_on() {
  [[ -n "$1" ]] || return 1
  az role assignment list --assignee "$1" --scope "$2" -o json |
    jq -e --arg s "$2" --arg r "$3" 'any(.[]; .roleDefinitionName == $r and (.scope | ascii_downcase) == ($s | ascii_downcase))' >/dev/null
}

# ci_pid: principal ID of the CI identity.
ci_pid() { az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query principalId -o tsv; }
