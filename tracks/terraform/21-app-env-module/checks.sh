# tf-21 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/app-env.sh"
export TF21_LIVE="$GH_OWNER/$LIVE_REPO" TF21_MODS="$GH_OWNER/$MODULES_REPO"
export TF21_SRC="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//app-env\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+\""
export TF21_OFFICER=b86a8fe4-44ce-4948-aee5-eccb2c155cd7
export -f appenv_kv_name appenv_kv_id appenv_kv_ok appenv_pe_ok appenv_identity_pid role_on ci_pid

check_code "the modules repo has app-env with an identity, a Key Vault and a private endpoint" \
  'm="${MODULES_DIR:-}/app-env" && for r in azurerm_user_assigned_identity azurerm_key_vault azurerm_private_endpoint; do grep -qsE "^resource[[:space:]]+\"$r\"" "$m"/*.tf || exit 1; done' \
  "write $MODULES_DIR/app-env/main.tf: azurerm_user_assigned_identity, azurerm_key_vault and azurerm_private_endpoint"

check_code "the vault uses RBAC, 7 days of soft delete, no purge protection, public access on" \
  'm="${MODULES_DIR:-}/app-env" && grep -qsE "^[[:space:]]*(rbac_authorization_enabled|enable_rbac_authorization)[[:space:]]*=[[:space:]]*true" "$m"/*.tf && grep -qsE "^[[:space:]]*soft_delete_retention_days[[:space:]]*=[[:space:]]*7([^0-9]|$)" "$m"/*.tf && ! grep -qsE "^[[:space:]]*purge_protection_enabled[[:space:]]*=[[:space:]]*true" "$m"/*.tf && ! grep -qsE "^[[:space:]]*public_network_access_enabled[[:space:]]*=[[:space:]]*false" "$m"/*.tf' \
  "azurerm_key_vault needs rbac_authorization_enabled = true and soft_delete_retention_days = 7, and neither purge_protection_enabled = true nor public_network_access_enabled = false"

check_code "the endpoint registers in DNS; the identity and the deployer get their roles; secrets wait for RBAC" \
  'm="${MODULES_DIR:-}/app-env" && grep -qsE "^[[:space:]]*private_dns_zone_group[[:space:]]*\{" "$m"/*.tf && grep -qsF "Key Vault Secrets User" "$m"/*.tf && grep -qsF "Key Vault Secrets Officer" "$m"/*.tf && grep -qsE "^resource[[:space:]]+\"time_sleep\"" "$m"/*.tf && grep -qsE "^resource[[:space:]]+\"azurerm_key_vault_secret\"" "$m"/*.tf' \
  "app-env needs a private_dns_zone_group on the endpoint, Key Vault Secrets User and Key Vault Secrets Officer assignments, a time_sleep and azurerm_key_vault_secret for var.secrets"

check_code "the modules repo accepts AZU-0013 with a reason, and its CI uses the ignore file" \
  'd="${MODULES_DIR:-}" && grep -qsE "AZU-0013" "$d/.trivyignore.yaml" && grep -qsE "^[[:space:]]+statement:" "$d/.trivyignore.yaml" && grep -qsE "trivy[^#]*--ignorefile[[:space:]=]+\.trivyignore\.yaml" "$d"/.github/workflows/*.y*ml' \
  "add $MODULES_REPO/.trivyignore.yaml (AZU-0013, paths app-env/main.tf, a statement) and pass --ignorefile .trivyignore.yaml to trivy in its CI"

check_code "CHANGELOG.md has a 2.1.0 entry for app-env" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && grep -qE "^#+[^0-9]*v?2\.1\.0" "$c" && grep -qF app-env "$c"' \
  "add a \"## 2.1.0\" entry to $MODULES_REPO/CHANGELOG.md that names the new app-env module"

check_code "env-dev calls app-env from the modules repo by tag and purges vaults on destroy" \
  'grep -rqsE "$TF21_SRC" terraform/env-dev --include="*.tf" && grep -rqsE "^[[:space:]]*purge_soft_delete_on_destroy[[:space:]]*=[[:space:]]*true" terraform/env-dev --include="*.tf"' \
  "terraform/env-dev needs module \"app_env\" with source \"git::https://github.com/$GH_OWNER/$MODULES_REPO.git//app-env?ref=v2.1.0\" and features { key_vault { purge_soft_delete_on_destroy = true } }"

check_code "bootstrap lets CI assign Key Vault Secrets Officer" \
  'grep -rqsiE "$TF21_OFFICER" terraform/bootstrap --include="*.tf"' \
  "add Key Vault Secrets Officer ($TF21_OFFICER) to the roles in the CI identity's RBAC Administrator condition in terraform/bootstrap"

check_code "the plan job's trivy scan skips downloaded modules" \
  'grep -qsE "trivy[^#]*--tf-exclude-downloaded-modules|^[[:space:]]+--tf-exclude-downloaded-modules" .github/workflows/terraform.yml' \
  "add --tf-exclude-downloaded-modules to the trivy step: the modules repo's CI scans the modules"

check "tag v2.1.0 in $TF21_MODS contains app-env" \
  'gh api "repos/$TF21_MODS/contents/app-env?ref=v2.1.0" --jq ".[].name" | grep -c "\.tf$" >/dev/null' \
  "tag the release after CI is green and push it: git tag -a v2.1.0 -m \"app-env\" && git push origin v2.1.0"

check "$(appenv_kv_name dev): RBAC, 7 days soft delete, no purge protection, public access on" \
  'appenv_kv_ok dev' \
  "expected Key Vault $(appenv_kv_name dev) in rg-$PREFIX-dev with RBAC authorization, soft delete 7 days, purge protection off and public network access Enabled"

check "pe-kv-$PREFIX-dev: snet-pe of vnet-$PREFIX-dev, approved, DNS zone group for privatelink.vaultcore.azure.net" \
  'appenv_pe_ok dev' \
  "expected private endpoint pe-kv-$PREFIX-dev in rg-$PREFIX-dev on vnet-$PREFIX-dev/snet-pe, connected (Approved) to the vault's \"vault\" sub-resource, with a DNS zone group for privatelink.vaultcore.azure.net"

check "id-$PREFIX-app-dev has Key Vault Secrets User on the vault" \
  'role_on "$(appenv_identity_pid dev)" "$(appenv_kv_id dev)" "Key Vault Secrets User"' \
  "expected identity id-$PREFIX-app-dev in rg-$PREFIX-dev with Key Vault Secrets User scoped to $(appenv_kv_name dev)"

check "CI may assign Key Vault Secrets Officer and holds it on the vault" \
  'pid="$(ci_pid)" && [[ -n "$pid" ]] && az role assignment list --assignee "$pid" --all -o json | jq -e "any(.[]; .roleDefinitionName == \"Role Based Access Control Administrator\" and ((.condition // \"\") | ascii_downcase | contains(env.TF21_OFFICER)))" >/dev/null && role_on "$pid" "$(appenv_kv_id dev)" "Key Vault Secrets Officer"' \
  "apply terraform/bootstrap locally (the condition must name $TF21_OFFICER), then let the pipeline give id-$PREFIX-github-ci Key Vault Secrets Officer on $(appenv_kv_name dev)"

check "the secret greeting is in the vault and you can read it" \
  '[[ -n "$(az keyvault secret show --vault-name "$(appenv_kv_name dev)" -n greeting --query value -o tsv)" ]]' \
  "expected secret greeting in $(appenv_kv_name dev), readable by you (bootstrap gives you Key Vault Secrets Officer on the subscription; new assignments can take a few minutes)"

check "the latest terraform run on main succeeded" \
  'ci_main_green "$TF21_LIVE"' \
  "the newest completed terraform.yml run on main in $TF21_LIVE is not green (is v2.1.0 pushed? did bootstrap get applied before the merge?)"
