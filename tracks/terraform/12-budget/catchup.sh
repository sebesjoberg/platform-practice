#!/usr/bin/env bash
# tf-12 catchup (after-push, cwd = LIVE_DIR): make sure the repo variable BUDGET_EMAIL exists;
# the workflow hands it to Terraform as TF_VAR_budget_email. An existing value is kept,
# otherwise git config user.email is used. tf-05's catchup runs this script before it dispatches
# the workflow whenever the workflow already references BUDGET_EMAIL. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
current="$(gh variable get BUDGET_EMAIL -R "$repo" 2>/dev/null || true)"
if [[ -n "$current" ]]; then
  echo "tf-12: kept the repo variable BUDGET_EMAIL"
  exit 0
fi

email="$(git config user.email || true)"
if [[ -z "$email" ]]; then
  echo "tf-12: git config user.email is not set. Set the budget alert address yourself:" >&2
  echo "  gh variable set BUDGET_EMAIL -R $repo --body <your email>" >&2
  exit 1
fi
if [[ "$email" == *@users.noreply.github.com ]]; then
  echo "tf-12: warning: $email is a GitHub noreply address; budget alerts sent there are lost." >&2
  echo "  Change it: gh variable set BUDGET_EMAIL -R $repo --body <your email>" >&2
fi
gh variable set BUDGET_EMAIL -R "$repo" --body "$email"
echo "tf-12: set the repo variable BUDGET_EMAIL to $email"
