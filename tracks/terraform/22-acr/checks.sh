# tf-22 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/app-env.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/acr-image.sh"
export TF22_REPO="$GH_OWNER/$LIVE_REPO" TF22_ACR="acr$PREFIX$SUFFIX"
export TF22_ACR_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-shared/providers/Microsoft.ContainerRegistry/registries/acr$PREFIX$SUFFIX"
export TF22_RG_JQ='.location == env.LOCATION and .tags.owner == env.OWNER_TAG and .tags.env == "hub" and .tags.managed_by == "terraform"'
export ACR_HELLO_IMAGE
export -f appenv_identity_pid role_on acr_name acr_hello_present

check_code "the shared stack has its own state key and a Basic registry" \
  'grep -rqsE "key[[:space:]]*=[[:space:]]*\"shared\.tfstate\"" terraform/shared --include="*.tf" && grep -rqsE "^resource[[:space:]]+\"azurerm_container_registry\"" terraform/shared --include="*.tf" && grep -rqsE "^[[:space:]]*sku[[:space:]]*=[[:space:]]*\"Basic\"" terraform/shared --include="*.tf"' \
  "terraform/shared needs backend \"azurerm\" with key = \"shared.tfstate\" and an azurerm_container_registry with sku = \"Basic\""

check_code "env-dev gives the app identity AcrPull on the shared registry" \
  'grep -rqsE "^data[[:space:]]+\"azurerm_container_registry\"" terraform/env-dev --include="*.tf" && grep -rqsE "role_definition_name[[:space:]]*=[[:space:]]*\"AcrPull\"" terraform/env-dev --include="*.tf"' \
  "in terraform/env-dev: data \"azurerm_container_registry\" for acr$PREFIX$SUFFIX and an azurerm_role_assignment with role_definition_name = \"AcrPull\" for the app identity"

check "rg-$PREFIX-shared exists in $LOCATION with the required tags" \
  'az group show -n "rg-$PREFIX-shared" -o json | jq -e "$TF22_RG_JQ" >/dev/null' \
  "expected rg-$PREFIX-shared in $LOCATION with tags owner=$OWNER_TAG, env=hub, managed_by=terraform (applied by the pipeline)"

check "$TF22_ACR is Basic, without the admin user, in rg-$PREFIX-shared" \
  'az acr show -g "rg-$PREFIX-shared" -n "$TF22_ACR" -o json | jq -e ".sku.name == \"Basic\" and .adminUserEnabled == false and .location == env.LOCATION" >/dev/null' \
  "expected container registry $TF22_ACR in rg-$PREFIX-shared ($LOCATION), SKU Basic, admin user disabled"

check "id-$PREFIX-app-dev has AcrPull on $TF22_ACR" \
  'role_on "$(appenv_identity_pid dev)" "$TF22_ACR_ID" AcrPull' \
  "expected an AcrPull assignment for id-$PREFIX-app-dev scoped to the registry $TF22_ACR"

check "$TF22_ACR holds hello:1.0" \
  'acr_hello_present' \
  "import it: az acr import --name $TF22_ACR --source mcr.microsoft.com/k8se/quickstart:latest --image hello:1.0"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "repos/$TF22_REPO/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF22_REPO is not green"
