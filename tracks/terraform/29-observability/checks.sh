# tf-29 checks (sourced by the grader; cwd = LIVE_DIR)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

# State reads: spoke_state_jq <key> <jq filter> (tracks/terraform/lib/spoke-ids.sh).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-ids.sh"
export TF29_REPO="$GH_OWNER/$LIVE_REPO" TF29_LAW="law-$PREFIX-platform"
export TF29_SNAP="$LAB_HOME/snapshots/tf-29.ids" TF29_GUIDS="$LAB_HOME/snapshots/tf-29.guids"
export TF29_LAW_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-hub/providers/Microsoft.OperationalInsights/workspaces/law-$PREFIX-platform"
export TF29_BLOCK_RE='^[[:space:]]*(import|removed)[[:space:]]*\{'
export TF29_RES_RE='resource[[:space:]]+"azurerm_(log_analytics_workspace|monitor_diagnostic_setting)"'
export TF29_OBS_JQ='def has($t): any(.resources[]?; .mode == "managed" and .type == $t);
  any(.resources[]?; .mode == "managed" and .type == "azurerm_log_analytics_workspace" and any(.instances[]; .attributes.name == env.TF29_LAW))
  and has("azurerm_monitor_diagnostic_setting")'
export TF29_LZ_JQ='all(.resources[]?; .mode != "managed" or (.type != "azurerm_log_analytics_workspace" and .type != "azurerm_monitor_diagnostic_setting"))'
export TF29_DIAG_JQ='[(.value? // .)[] | select((.workspaceId // "" | ascii_downcase) == (env.TF29_LAW_ID | ascii_downcase)) | [.logs[]? | select(.enabled) | .category]] | any(contains(["Administrative", "Security", "Policy"]))'

# tf29_obs_stack: terraform/observability has its own state key and declares both resources.
tf29_obs_stack() {
  local d=terraform/observability
  grep --exclude-dir=.terraform -rqsE 'backend[[:space:]]+"azurerm"' "$d" --include='*.tf' &&
    grep --exclude-dir=.terraform -rqsE 'key[[:space:]]*=[[:space:]]*"observability\.tfstate"' "$d" --include='*.tf' &&
    grep --exclude-dir=.terraform -rqsE 'resource[[:space:]]+"azurerm_log_analytics_workspace"' "$d" --include='*.tf' &&
    grep --exclude-dir=.terraform -rqsE 'resource[[:space:]]+"azurerm_monitor_diagnostic_setting"' "$d" --include='*.tf'
}
# tf29_law_unchanged: the workspace still exists under the snapshotted resource ID (or the
# name-built one), and its customerId is the recorded baseline when there is one.
tf29_law_unchanged() {
  local j want
  j="$(az monitor log-analytics workspace show -g "rg-$PREFIX-hub" -n "$TF29_LAW" -o json)" || return 1
  want="$TF29_LAW_ID"
  [[ -s "$TF29_SNAP" ]] && want="$(head -n1 "$TF29_SNAP")"
  [[ "$(jq -r '.id | ascii_downcase' <<<"$j")" == "$(tr '[:upper:]' '[:lower:]' <<<"$want")" ]] || return 1
  [[ -s "$TF29_GUIDS" ]] || return 0
  [[ "$(jq -r '.customerId' <<<"$j")" == "$(awk '{ print $2 }' "$TF29_GUIDS")" ]]
}
export -f tf29_obs_stack tf29_law_unchanged spoke_state_jq

check_code "observability has its own state key and owns the workspace and the Activity Log export" \
  'tf29_obs_stack' \
  "terraform/observability needs backend \"azurerm\" with key = \"observability.tfstate\", azurerm_log_analytics_workspace and azurerm_monitor_diagnostic_setting"

check_code "landing-zone no longer declares the workspace or the diagnostic setting" \
  '[[ -d terraform/landing-zone ]] && ! grep --exclude-dir=.terraform -rqsE "$TF29_RES_RE" terraform/landing-zone --include="*.tf"' \
  "terraform/landing-zone still declares azurerm_log_analytics_workspace or azurerm_monitor_diagnostic_setting: they belong to observability now"

check_code "the move is finished: no import or removed blocks left" \
  'tf29_obs_stack && ! grep --exclude-dir=.terraform -rqsE "$TF29_BLOCK_RE" terraform/landing-zone terraform/observability --include="*.tf"' \
  "delete the removed and import blocks once the move is applied (PR 2): an import of a missing object fails every rebuild"

check "$TF29_LAW has the same resource ID and customerId as before the move" \
  'tf29_law_unchanged' \
  "law-$PREFIX-platform is gone, or its customerId differs from $TF29_GUIDS: it was destroyed and created again"

check "observability.tfstate holds the workspace and the diagnostic setting" \
  'spoke_state_jq observability.tfstate "$TF29_OBS_JQ"' \
  "observability.tfstate must manage azurerm_log_analytics_workspace $TF29_LAW and azurerm_monitor_diagnostic_setting (has the import been applied?)"

check "landing-zone.tfstate holds neither any more" \
  'spoke_state_jq landing-zone.tfstate "$TF29_LZ_JQ"' \
  "landing-zone.tfstate still manages the workspace or the diagnostic setting: removed { from = ... lifecycle { destroy = false } }"

check "the subscription's Activity Log still goes to $TF29_LAW" \
  'az monitor diagnostic-settings subscription list -o json | jq -e "$TF29_DIAG_JQ"' \
  "expected a subscription diagnostic setting with workspace law-$PREFIX-platform and at least Administrative, Security and Policy enabled"

check "latest completed terraform run on main succeeded" \
  'ci_main_green "$TF29_REPO"' \
  "the newest completed terraform.yml run on main is not green; open it in the Actions tab"
