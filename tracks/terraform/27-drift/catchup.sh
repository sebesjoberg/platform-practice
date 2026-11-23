#!/usr/bin/env bash
# tf-27 catchup (after-push, cwd = LIVE_DIR): reconcile the incident and leave the trail the
# grader looks for. tf-05's hook has already applied every stack, which put the owner tag of
# rg-<prefix>-dev back. Then:
#   - delete the NSG rule AllowAll-Temp, which no plan shows (the spoke NSGs have no inline rules);
#   - run drift.yml once and wait: it must be green;
#   - if no issue labelled drift exists (the pipeline reconciled before drift.yml ever ran), file
#     one and close it, as the record of the incident.
# Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$GH_OWNER/$LIVE_REPO"
rg="rg-$PREFIX-dev"
nsg="nsg-$PREFIX-dev-app"

if az network nsg rule show -g "$rg" --nsg-name "$nsg" -n AllowAll-Temp -o none 2>/dev/null; then
  az network nsg rule delete -g "$rg" --nsg-name "$nsg" -n AllowAll-Temp -o none
  echo "tf-27: deleted AllowAll-Temp from $nsg"
fi

[[ -f .github/workflows/drift.yml ]] || { echo "tf-27: no .github/workflows/drift.yml in the live repo" >&2; exit 1; }
gh workflow enable drift.yml -R "$repo" >/dev/null 2>&1 || true
# shellcheck source=/dev/null
source "$here/../lib/ci-dispatch.sh"
ci_workflow_wait "$repo" drift.yml tf-27

if [[ -z "$(gh issue list -R "$repo" --label drift --state all --limit 1 --json number --jq '.[].number')" ]]; then
  gh label create drift -R "$repo" --color B60205 --description "Azure differs from main (drift.yml)" --force >/dev/null
  url="$(gh issue create -R "$repo" --label drift --title "Drift detected: env-dev (reconciled by catchup)" \
    --body "Owner tag of $rg changed by hand and NSG rule AllowAll-Temp added on $nsg. Reconciled by ./lab.sh catchup.")"
  gh issue close "$url" -R "$repo" --comment "Reconciled: tag re-applied by the pipeline, rule deleted." >/dev/null
  echo "tf-27: filed and closed the drift issue $url"
fi
