# tf-23 checks (sourced by the grader; cwd = LIVE_DIR)

export TF23_REPO="$GH_OWNER/$LIVE_REPO" TF23_RG="rg-$PREFIX-dev"
export TF23_CAE="cae-$PREFIX-dev" TF23_CA="ca-$PREFIX-hello-dev"
export TF23_LOGIN="acr$PREFIX$SUFFIX.azurecr.io" TF23_KV="kv-$PREFIX-dev-$SUFFIX"
export TF23_UAMI_SUFFIX="/providers/microsoft.managedidentity/userassignedidentities/id-$PREFIX-app-dev"
export TF23_ENV_JQ='(.properties.vnetConfiguration.infrastructureSubnetId // "" | ascii_downcase | endswith("/virtualnetworks/vnet-" + env.PREFIX + "-dev/subnets/snet-aca")) and (.properties.vnetConfiguration.internal // false) == false'
export TF23_APP_JQ='def me: ascii_downcase | endswith(env.TF23_UAMI_SUFFIX);
  (.identity.userAssignedIdentities // {} | keys | any(me))
  and any(.properties.configuration.registries[]?; .server == env.TF23_LOGIN and (.identity // "" | me))
  and any(.properties.configuration.secrets[]?; (.keyVaultUrl // "" | ascii_downcase | startswith("https://" + env.TF23_KV + ".vault.azure.net/secrets/")) and (.identity // "" | me))
  and any(.properties.template.containers[]?; .image == env.TF23_LOGIN + "/hello:1.0")
  and .properties.configuration.ingress.external == true'

check_code "env-dev declares a VNet-integrated Container Apps environment and the app" \
  'grep -rqsE "^resource[[:space:]]+\"azurerm_container_app_environment\"" terraform/env-dev --include="*.tf" && grep -rqsE "^[[:space:]]*infrastructure_subnet_id[[:space:]]*=" terraform/env-dev --include="*.tf" && grep -rqsE "^resource[[:space:]]+\"azurerm_container_app\"" terraform/env-dev --include="*.tf"' \
  "terraform/env-dev needs azurerm_container_app_environment (with infrastructure_subnet_id = snet-aca) and azurerm_container_app"

check_code "the app pulls with an identity and references a Key Vault secret" \
  'grep -rqsE "^[[:space:]]*key_vault_secret_id[[:space:]]*=" terraform/env-dev --include="*.tf" && awk "/^[[:space:]]*registry[[:space:]]*\\{/ { r = 1 } r && /^[[:space:]]*identity[[:space:]]*=/ { f = 1 } r && /^[[:space:]]*\\}/ { r = 0 } END { exit !f }" $(find terraform/env-dev -name "*.tf")' \
  "in azurerm_container_app: a registry block with identity = <the app identity ID> (no password) and a secret with key_vault_secret_id"

check "$TF23_CAE is in snet-aca of vnet-$PREFIX-dev, with external ingress" \
  'az containerapp env show -g "$TF23_RG" -n "$TF23_CAE" -o json | jq -e "$TF23_ENV_JQ" >/dev/null' \
  "expected Container Apps environment $TF23_CAE in $TF23_RG with infrastructure subnet vnet-$PREFIX-dev/snet-aca and a public (not internal) load balancer"

check "$TF23_CA runs $TF23_LOGIN/hello:1.0 as id-$PREFIX-app-dev and reads the greeting from Key Vault" \
  'az containerapp show -g "$TF23_RG" -n "$TF23_CA" -o json | jq -e "$TF23_APP_JQ" >/dev/null' \
  "expected $TF23_CA with user-assigned identity id-$PREFIX-app-dev, registry $TF23_LOGIN pulled with that identity, a secret referencing https://$TF23_KV.vault.azure.net/secrets/... with that identity, image $TF23_LOGIN/hello:1.0 and external ingress"

check "https://<fqdn>/ of $TF23_CA answers 200" \
  'fqdn="$(az containerapp show -g "$TF23_RG" -n "$TF23_CA" --query properties.configuration.ingress.fqdn -o tsv)" && [[ -n "$fqdn" ]] && [[ "$(curl -sS -o /dev/null -w "%{http_code}" --max-time 40 "https://$fqdn/")" == 200 ]]' \
  "curl -fsS https://\$(az containerapp show -g $TF23_RG -n $TF23_CA --query properties.configuration.ingress.fqdn -o tsv)/ must answer 200 (check the revision's status and system logs: az containerapp logs show --type system)"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "repos/$TF23_REPO/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF23_REPO is not green"
