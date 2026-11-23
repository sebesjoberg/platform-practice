# tf-24 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/app-env.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export TF24_WF=.github/workflows/terraform.yml TF24_REPO="$GH_OWNER/$LIVE_REPO"
export TF24_MOD="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//"
export TF24_ACR_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-shared/providers/Microsoft.ContainerRegistry/registries/acr$PREFIX$SUFFIX"

# tf24_prod_job <workflow>: a job other than plan and apply runs in the environment prod and
# needs apply, and the apply job leaves env-prod out (mentions it outside comments).
tf24_prod_job() {
  local j b found=1
  for j in $(ci_job_ids "$1"); do
    [[ "$j" == plan || "$j" == apply ]] && continue
    b="$(ci_job "$1" "$j" | grep -vE '^[[:space:]]*#')"
    if grep -qE '^[[:space:]]+(environment|name):[[:space:]]*"?prod"?[[:space:]]*$' <<<"$b" &&
      grep -qE '^[[:space:]]+needs:' <<<"$b" &&
      grep -qE '^[[:space:]]+needs:.*[^A-Za-z0-9_-]apply([^A-Za-z0-9_-]|$)|^[[:space:]]+-[[:space:]]+apply[[:space:]]*$' <<<"$b"; then
      found=0
    fi
  done
  [[ $found -eq 0 ]] && ci_job "$1" apply | grep -vE '^[[:space:]]*#' | grep -q env-prod
}
export -f appenv_kv_name appenv_kv_id appenv_kv_ok appenv_pe_ok appenv_identity_pid role_on ci_job ci_job_ids ci_plan_independent tf24_prod_job

check_code "env-prod uses spoke v2 (vnet_cidr) and app-env from the modules repo" \
  'grep -rqsE "${TF24_MOD}spoke\?ref=v[2-9][0-9]*\.[0-9]+\.[0-9]+\"" terraform/env-prod --include="*.tf" && grep -rqsE "^[[:space:]]*vnet_cidr[[:space:]]*=" terraform/env-prod --include="*.tf" && grep -rqsE "${TF24_MOD}app-env\?ref=v[0-9]+\.[0-9]+\.[0-9]+\"" terraform/env-prod --include="*.tf" && grep -rqsE "^[[:space:]]*purge_soft_delete_on_destroy[[:space:]]*=[[:space:]]*true" terraform/env-prod --include="*.tf"' \
  "terraform/env-prod needs spoke ?ref=v2.0.0 with vnet_cidr, module \"app_env\" from //app-env?ref=v2.1.0 and features { key_vault { purge_soft_delete_on_destroy = true } }, like env-dev"

check_code "env-prod gives its app identity AcrPull on the shared registry" \
  'grep -rqsE "Microsoft\.ContainerRegistry/registries/|^data[[:space:]]+\"azurerm_container_registry\"" terraform/env-prod --include="*.tf" && grep -rqsE "role_definition_name[[:space:]]*=[[:space:]]*\"AcrPull\"" terraform/env-prod --include="*.tf"' \
  "in terraform/env-prod: AcrPull on the registry (ID built from names, as in env-dev) for module.app_env's identity, as in env-dev"

check_code "a job in the prod environment applies env-prod after apply, and apply skips it" \
  'tf24_prod_job "$TF24_WF"' \
  "add a job (apply-prod) with environment: prod and needs: apply that applies terraform/env-prod, and leave env-prod out of the apply job's stack list"

check_code "plan still needs no other job" \
  'ci_plan_independent "$TF24_WF" && [[ "$(ci_job_ids "$TF24_WF" | grep -c .)" -ge 3 ]]' \
  "keep plan (no needs:) and apply, and add the prod job as a third job"

check "the newest prod deployment ran in the environment prod and succeeded" \
  'id="$(gh api "repos/$TF24_REPO/deployments?environment=prod&per_page=1" --jq ".[0].id // empty")" && [[ -n "$id" ]] && [[ "$(gh api "repos/$TF24_REPO/deployments/$id/statuses?per_page=1" --jq ".[0].state")" == success ]]' \
  "no successful deployment to the environment prod: merge, then approve the waiting apply-prod job (Actions tab, Review deployments)"

check "$(appenv_kv_name prod): RBAC, 7 days soft delete, no purge protection, public access on" \
  'appenv_kv_ok prod' \
  "expected Key Vault $(appenv_kv_name prod) in rg-$PREFIX-prod with RBAC authorization, soft delete 7 days, purge protection off and public network access Enabled"

check "pe-kv-$PREFIX-prod: snet-pe of vnet-$PREFIX-prod, approved, DNS zone group for privatelink.vaultcore.azure.net" \
  'appenv_pe_ok prod' \
  "expected private endpoint pe-kv-$PREFIX-prod in rg-$PREFIX-prod on vnet-$PREFIX-prod/snet-pe, approved, with a DNS zone group for privatelink.vaultcore.azure.net"

check "id-$PREFIX-app-prod has Key Vault Secrets User on its vault and AcrPull on the registry" \
  'pid="$(appenv_identity_pid prod)" && role_on "$pid" "$(appenv_kv_id prod)" "Key Vault Secrets User" && role_on "$pid" "$TF24_ACR_ID" AcrPull' \
  "expected identity id-$PREFIX-app-prod in rg-$PREFIX-prod with Key Vault Secrets User on $(appenv_kv_name prod) and AcrPull on acr$PREFIX$SUFFIX"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "repos/$TF24_REPO/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF24_REPO is not green (a rejected or timed-out apply-prod counts as failed)"
