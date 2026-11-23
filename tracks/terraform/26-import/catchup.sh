#!/usr/bin/env bash
# tf-26 catchup (cwd = LIVE_DIR): the reference declares the legacy resources in landing-zone
# (azurerm_resource_group.legacy, azurerm_storage_account.legacy) without import blocks, so a
# pipeline run would try to create what setup.sh created by hand and fail with "already exists".
# This brings landing-zone's state in line first, locally, with your own az login:
#   - a resource the state already holds under another address (your own code) is moved to the
#     reference's address with terraform state mv;
#   - one that exists in Azure but is missing from the state is imported;
#   - one that doesn't exist in Azure at all (setup.sh never ran) is left to the pipeline.
# tf-05's catchup runs this before it dispatches the pipeline, whenever landing-zone declares the
# legacy account; its own after-push call is then a no-op. Idempotent.
set -euo pipefail

: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID not set; run ./lab.sh init}"
stack=terraform/landing-zone
grep --exclude-dir=.terraform -rqsE 'resource[[:space:]]+"azurerm_storage_account"[[:space:]]+"legacy"' "$stack" --include='*.tf' || {
  echo "tf-26: landing-zone doesn't declare the legacy account; nothing to do"
  exit 0
}

rg="rg-$PREFIX-legacy"
sa="st${PREFIX}legacy$SUFFIX"
rg_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$rg"
sa_id="$rg_id/providers/Microsoft.Storage/storageAccounts/$sa"

# A local import evaluates the whole configuration, so every variable needs a value. These are
# never sent anywhere by an import; values already in the environment win.
export TF_VAR_budget_email="${TF_VAR_budget_email:-catchup@example.invalid}"
terraform -chdir="$stack" init -input=false </dev/null >/dev/null

# tf26_adopt <type> <reference address> <name> <id> <exists in Azure: yes|no>
tf26_adopt() {
  local type=$1 want=$2 name=$3 id=$4 exists=$5 have
  have="$(terraform -chdir="$stack" state pull </dev/null | jq -r --arg t "$type" --arg n "$name" '
    .resources[]? | select(.mode == "managed" and .type == $t and any(.instances[]; .attributes.name == $n))
    | ((if .module then .module + "." else "" end) + .type + "." + .name)' | head -n1)"
  if [[ "$have" == "$want" ]]; then
    echo "tf-26: $want is already in landing-zone's state"
  elif [[ -n "$have" ]]; then
    terraform -chdir="$stack" state mv -lock-timeout=5m "$have" "$want" </dev/null
    echo "tf-26: moved $have to $want in landing-zone's state"
  elif [[ "$exists" == yes ]]; then
    terraform -chdir="$stack" import -input=false -lock-timeout=5m "$want" "$id" </dev/null
    echo "tf-26: imported $name into landing-zone's state"
  else
    echo "tf-26: $name doesn't exist; the pipeline creates it"
  fi
}

rg_exists=no
sa_exists=no
[[ "$(az group exists -n "$rg" -o tsv | tr -d '\r')" == true ]] && rg_exists=yes
if [[ $rg_exists == yes ]] && az storage account show -g "$rg" -n "$sa" -o none 2>/dev/null; then
  sa_exists=yes
fi
tf26_adopt azurerm_resource_group azurerm_resource_group.legacy "$rg" "$rg_id" "$rg_exists"
tf26_adopt azurerm_storage_account azurerm_storage_account.legacy "$sa" "$sa_id" "$sa_exists"
