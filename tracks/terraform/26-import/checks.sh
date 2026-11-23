# tf-26 checks (sourced by the grader; cwd = LIVE_DIR)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

# Spoke helpers: spoke_state_jq <key> <jq filter> downloads a state blob and evaluates the filter.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-ids.sh"
export TF26_RG="rg-$PREFIX-legacy" TF26_SA="st${PREFIX}legacy$SUFFIX" TF26_REPO="$GH_OWNER/$LIVE_REPO"
export TF26_SNAP="$LAB_HOME/snapshots/tf-26.ids"
export TF26_IMPORT_RE='^[[:space:]]*import[[:space:]]*\{'
export TF26_TAGS_JQ='.tags.owner == env.OWNER_TAG and .tags.managed_by == "terraform" and (.tags.env // "") != ""'
export TF26_STATE_JQ='def has($t; $n): any(.resources[]?; .mode == "managed" and .type == $t and any(.instances[]; .attributes.name == $n)); has("azurerm_resource_group"; env.TF26_RG) and has("azurerm_storage_account"; env.TF26_SA)'

# tf26_declared: landing-zone declares the legacy group and a storage account named st<prefix>legacy...
tf26_declared() {
  local d=terraform/landing-zone
  grep -rqsE 'resource[[:space:]]+"azurerm_storage_account"' "$d" --include='*.tf' &&
    grep -rqsE '"st(\$\{var\.prefix\}|[a-z]{2,6})legacy' "$d" --include='*.tf' &&
    grep -rqsE '"rg-(\$\{var\.prefix\}|[a-z]{2,6})-legacy"' "$d" --include='*.tf'
}
# tf26_not_recreated: the account's creation time is the one setup.sh recorded (no snapshot, as
# after a catchup that created the account itself: nothing to compare).
tf26_not_recreated() {
  local id created now
  [[ -s "$TF26_SNAP" ]] || return 0
  { read -r id; read -r created; } <"$TF26_SNAP"
  now="$(az storage account show --ids "$id" --query creationTime -o tsv | tr -d '\r')"
  [[ -n "$now" && "$now" == "$created" ]]
}
export -f tf26_declared tf26_not_recreated spoke_state_jq

check_code "landing-zone declares rg-$PREFIX-legacy and st${PREFIX}legacy$SUFFIX" \
  'tf26_declared' \
  "declare azurerm_resource_group \"rg-\${var.prefix}-legacy\" and azurerm_storage_account \"st\${var.prefix}legacy\${var.suffix}\" in terraform/landing-zone"

check_code "the import is finished: legacy code in place, no import blocks left" \
  'tf26_declared && ! grep -rqsE "$TF26_IMPORT_RE" terraform --include="*.tf"' \
  "delete the import blocks once PR 1 is applied (PR 2): an import of a missing object fails every rebuild from scratch"

check "$TF26_RG carries owner=$OWNER_TAG and managed_by=terraform" \
  'az group show -n "$TF26_RG" -o json | jq -e "$TF26_TAGS_JQ"' \
  "expected the tags owner=$OWNER_TAG, env and managed_by=terraform on $TF26_RG (merged and applied?)"

check "landing-zone.tfstate holds $TF26_RG and $TF26_SA" \
  'spoke_state_jq landing-zone.tfstate "$TF26_STATE_JQ"' \
  "landing-zone.tfstate must manage azurerm_resource_group $TF26_RG and azurerm_storage_account $TF26_SA (has the import been applied?)"

check "$TF26_SA was imported, not recreated" \
  'tf26_not_recreated' \
  "the creation time of $TF26_SA differs from $TF26_SNAP: the account was deleted and created again, and the finance team's files with it"

check "latest completed terraform run on main succeeded" \
  'ci_main_green "$TF26_REPO"' \
  "the newest completed terraform.yml run on main is not green; open it in the Actions tab"
