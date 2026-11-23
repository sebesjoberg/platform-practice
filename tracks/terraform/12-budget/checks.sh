# tf-12 checks (sourced by the grader; cwd = LIVE_DIR)

export TF12_WF=.github/workflows/terraform.yml TF12_REPO="$GH_OWNER/$LIVE_REPO"
export TF12_BUDGET_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/budget-$PREFIX-monthly?api-version=2021-10-01"
export TF12_AG_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-$PREFIX-hub/providers/microsoft.insights/actionGroups/ag-$PREFIX-budget"
# TF_VAR_budget_email: ${{ vars.BUDGET_EMAIL }} at workflow level (indent 2) or in both jobs.
export TF12_ENV_AWK='/^[[:space:]]*TF_VAR_budget_email:[[:space:]]*"?\$\{\{[[:space:]]*vars\.BUDGET_EMAIL[[:space:]]*\}\}/ { n++; match($0, /^ */); if (RLENGTH == 2) top = 1 } END { exit !(top || n >= 2) }'
export TF12_BUDGET_JQ='def n($t; $k): any(.properties.notifications[]; .enabled and .threshold == $t and .thresholdType == $k and any(.contactGroups[]?; ascii_downcase == (env.TF12_AG_ID | ascii_downcase))); .properties.amount == 300 and .properties.timeGrain == "Monthly" and n(80; "Actual") and n(100; "Forecasted")'

check_code "landing-zone declares the budget and its action group" \
  'grep -rqsE "resource[[:space:]]+\"azurerm_consumption_budget_subscription\"" terraform --include="*.tf" && grep -rqsE "resource[[:space:]]+\"azurerm_monitor_action_group\"" terraform --include="*.tf"' \
  "declare azurerm_consumption_budget_subscription and azurerm_monitor_action_group in terraform/landing-zone"

check_code "the budget email is a sensitive variable, not a literal" \
  'b="$(find terraform -name "*.tf" -not -path "*/.terraform/*" -exec awk "/^variable[[:space:]]+\"budget_email\"/ { on = 1 } on { print } on && /^}/ { on = 0 }" {} +)" && grep -qE "sensitive[[:space:]]*=[[:space:]]*true" <<<"$b" && ! grep -qE "^[[:space:]]*default[[:space:]]*=" <<<"$b"' \
  "declare variable \"budget_email\" with sensitive = true and no default (the value comes from TF_VAR_budget_email)"

check_code "the workflow passes TF_VAR_budget_email from vars.BUDGET_EMAIL to both jobs" \
  '[[ -f "$TF12_WF" ]] && awk "$TF12_ENV_AWK" "$TF12_WF"' \
  "add TF_VAR_budget_email: \${{ vars.BUDGET_EMAIL }} to the workflow-level env (or to both jobs) in $TF12_WF"

check "repo variable BUDGET_EMAIL is set" \
  '[[ -n "$(gh api "repos/$TF12_REPO/actions/variables/BUDGET_EMAIL" --jq .value)" ]]' \
  "set it: gh variable set BUDGET_EMAIL -R $TF12_REPO --body <your email>"

check "ag-$PREFIX-budget mails the BUDGET_EMAIL address" \
  'want="$(gh api "repos/$TF12_REPO/actions/variables/BUDGET_EMAIL" --jq .value)" && [[ -n "$want" ]] && az monitor action-group show -g "rg-$PREFIX-hub" -n "ag-$PREFIX-budget" -o json | jq -e --arg w "$want" "any(.emailReceivers[]; (.emailAddress | ascii_downcase) == (\$w | ascii_downcase))"' \
  "expected action group ag-$PREFIX-budget in rg-$PREFIX-hub with an email receiver for the BUDGET_EMAIL address"

check "budget-$PREFIX-monthly: 300 monthly, 80 % actual and 100 % forecasted to ag-$PREFIX-budget" \
  'az rest --method get --url "$TF12_BUDGET_URL" -o json | jq -e "$TF12_BUDGET_JQ"' \
  "expected subscription budget budget-$PREFIX-monthly, amount 300, Monthly, alerts at 80 (Actual) and 100 (Forecasted) with contact group ag-$PREFIX-budget"
