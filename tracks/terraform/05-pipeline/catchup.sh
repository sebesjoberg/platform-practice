#!/usr/bin/env bash
# tf-05 catchup (after-push, cwd = LIVE_DIR): set the repo variables, then dispatch the
# terraform workflow on main and wait for it (the push run may have started before the
# variables existed, and fresh role assignments can take minutes). Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
client_id="$(az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query clientId -o tsv)"
[[ -n "$client_id" ]] || { echo "tf-05: id-$PREFIX-github-ci not found (tf-04)" >&2; exit 1; }
gh variable set AZURE_CLIENT_ID -R "$repo" --body "$client_id"
gh variable set AZURE_TENANT_ID -R "$repo" --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID -R "$repo" --body "$SUBSCRIPTION_ID"

# The run below applies the tree catchup just pushed, which may be a later task's reference.
# From tf-12 on the workflow also needs the repo variable BUDGET_EMAIL, and tf-12's hook runs
# after this one, so set it now (tf-12's catchup.sh is the single place that knows how).
if grep -qs 'vars\.BUDGET_EMAIL' .github/workflows/terraform.yml; then
  bash "$(dirname "${BASH_SOURCE[0]}")/../12-budget/catchup.sh"
fi
# From tf-19 the env stacks pull the spoke module from the modules repo by tag, and tf-19/tf-20's
# hooks (which create those tags) run after this one: create the tags the tree pins first.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
modules_tag_pinned

runs() { gh run list -R "$repo" --workflow terraform.yml --event workflow_dispatch --limit 20 --json databaseId --jq '.[].databaseId'; }

for attempt in 1 2 3; do
  known=" $(runs | tr '\n' ' ') "
  gh workflow run terraform.yml -R "$repo" --ref main -f stacks=all
  id=""
  for _ in $(seq 1 30); do
    for r in $(runs); do
      if [[ "$known" != *" $r "* ]]; then id=$r; break; fi
    done
    [[ -n "$id" ]] && break
    sleep 5
  done
  [[ -n "$id" ]] || { echo "tf-05: could not find the dispatched run" >&2; exit 1; }
  echo "tf-05: waiting for run $id"
  if gh run watch "$id" -R "$repo" --interval 15 --exit-status >/dev/null; then
    echo "tf-05: run $id succeeded"
    exit 0
  fi
  echo "tf-05: run $id failed (attempt $attempt/3), retrying in 60s" >&2
  sleep 60
done
echo "tf-05: the terraform workflow keeps failing; see gh run list -R $repo" >&2
exit 1
