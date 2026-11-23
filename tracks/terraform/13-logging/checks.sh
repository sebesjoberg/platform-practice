# tf-13 checks (sourced by the grader; cwd = LIVE_DIR)
# Code checks search every stack: tf-29 moves the workspace into an observability stack.

export TF13_LAW_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-hub/providers/Microsoft.OperationalInsights/workspaces/law-$PREFIX-platform"
export TF13_LAW_JQ='.location == env.LOCATION and .sku.name == "PerGB2018" and .retentionInDays == 30 and .workspaceCapping.dailyQuotaGb == 0.1'
export TF13_DIAG_JQ='[(.value? // .)[] | select((.workspaceId // "" | ascii_downcase) == (env.TF13_LAW_ID | ascii_downcase)) | [.logs[]? | select(.enabled) | .category]] | any(contains(["Administrative", "Security", "Policy"]))'

check_code "a Log Analytics workspace with a 0.1 GB daily cap is declared" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_log_analytics_workspace\"" terraform --include="*.tf" && grep --exclude-dir=.terraform -rqsE "daily_quota_gb[[:space:]]*=[[:space:]]*0?\.1([^0-9]|$)" terraform --include="*.tf"' \
  "declare azurerm_log_analytics_workspace with daily_quota_gb = 0.1"

check_code "a diagnostic setting is declared (Activity Log export)" \
  'grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_monitor_diagnostic_setting\"" terraform --include="*.tf"' \
  "declare an azurerm_monitor_diagnostic_setting on the subscription that sends the Activity Log to the workspace"

check "law-$PREFIX-platform: PerGB2018, 30 days, 0.1 GB/day cap" \
  'az monitor log-analytics workspace show -g "rg-$PREFIX-hub" -n "law-$PREFIX-platform" -o json | jq -e "$TF13_LAW_JQ"' \
  "expected law-$PREFIX-platform in rg-$PREFIX-hub ($LOCATION), SKU PerGB2018, retention 30, daily cap 0.1 GB"

check "the subscription's Activity Log goes to law-$PREFIX-platform" \
  'az monitor diagnostic-settings subscription list -o json | jq -e "$TF13_DIAG_JQ"' \
  "expected a subscription diagnostic setting with workspace law-$PREFIX-platform and at least Administrative, Security and Policy enabled"
