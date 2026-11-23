# tf-27 checks (sourced by the grader; cwd = LIVE_DIR)

export TF27_WF=.github/workflows/drift.yml TF27_REPO="$GH_OWNER/$LIVE_REPO"
export TF27_START="$LAB_HOME/snapshots/tf-27.start"
# Inbound allow rules from anywhere (the incident's AllowAll-Temp or anything like it).
export TF27_NSG_JQ='[.[] | select(.name == "AllowAll-Temp" or (.direction == "Inbound" and .access == "Allow"
  and ((.sourceAddressPrefix // "") as $s | $s == "*" or $s == "Internet" or $s == "0.0.0.0/0")))] | length == 0'

# tf27_wf_ok: drift.yml runs on a schedule and on demand, plans with -detailed-exitcode through
# stacks.sh, files issues labelled drift and has the permissions for it.
tf27_wf_ok() {
  local f=$TF27_WF
  [[ -f "$f" ]] &&
    grep -qE '^[[:space:]]+schedule:' "$f" && grep -qE '^[[:space:]]*-[[:space:]]*cron:' "$f" &&
    grep -qE '^[[:space:]]+workflow_dispatch:' "$f" &&
    grep -qE -- '-detailed-exitcode' "$f" && grep -qF 'stacks.sh' "$f" &&
    grep -qE 'label[[:space:]]+drift|--label[[:space:]]*=?[[:space:]]*"?drift' "$f" &&
    grep -qE 'issues:[[:space:]]*write' "$f" && grep -qE 'id-token:[[:space:]]*write' "$f"
}
# tf27_green_after_start: the newest completed drift.yml run succeeded and, when setup.sh
# recorded the incident, started after it.
tf27_green_after_start() {
  local start=0
  [[ -s "$TF27_START" ]] && start="$(cat "$TF27_START")"
  gh api "repos/$TF27_REPO/actions/workflows/drift.yml/runs?status=completed&per_page=1" \
    --jq '.workflow_runs[0] // {}' |
    jq -e --argjson s "$start" '.conclusion == "success" and ((.run_started_at // .created_at) | fromdateiso8601) >= $s' >/dev/null
}
export -f tf27_wf_ok tf27_green_after_start

check_code "drift.yml: schedule, workflow_dispatch, plan -detailed-exitcode per stack, drift issues" \
  'tf27_wf_ok' \
  "$TF27_WF needs on: schedule (cron) and workflow_dispatch, terraform plan -detailed-exitcode for each stack from .github/scripts/stacks.sh, an issue labelled drift on exit code 2, and permissions issues: write and id-token: write"

check "workflow drift.yml is active on GitHub" \
  '[[ "$(gh api "repos/$TF27_REPO/actions/workflows/drift.yml" --jq .state)" == active ]]' \
  "no active workflow drift.yml in $TF27_REPO (merged to main? disabled by ./lab.sh pause? gh workflow enable drift.yml)"

check "an issue labelled drift exists" \
  '[[ -n "$(gh api "repos/$TF27_REPO/issues?labels=drift&state=all&per_page=1" --jq ".[0].number // empty")" ]]' \
  "no issue labelled drift in $TF27_REPO: run drift.yml while the drift is still there (gh workflow run drift.yml)"

check "the newest drift.yml run is green (every stack plans clean)" \
  'tf27_green_after_start' \
  "the newest completed drift.yml run is not green, or older than the incident: reconcile, then gh workflow run drift.yml"

check "rg-$PREFIX-dev carries owner=$OWNER_TAG again" \
  '[[ "$(az group show -n "rg-$PREFIX-dev" --query tags.owner -o tsv)" == "$OWNER_TAG" ]]' \
  "the owner tag of rg-$PREFIX-dev is not $OWNER_TAG: apply env-dev (gh workflow run terraform.yml -f stacks=env-dev)"

check "nsg-$PREFIX-dev-app allows nothing inbound from anywhere" \
  'az network nsg rule list -g "rg-$PREFIX-dev" --nsg-name "nsg-$PREFIX-dev-app" -o json | jq -e "$TF27_NSG_JQ"' \
  "nsg-$PREFIX-dev-app still has AllowAll-Temp or another inbound allow rule from any source; Terraform's plan doesn't show it (az network nsg rule list ...)"
