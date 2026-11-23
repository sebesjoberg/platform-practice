#!/usr/bin/env bash
# tf-12 catchup (after-push, cwd = LIVE_DIR): make sure the repo secret BUDGET_EMAIL exists; the
# workflow hands it to Terraform as TF_VAR_budget_email. A secret, not a variable: the repo is
# public and GitHub prints env values in step logs, masking only secrets. An existing secret is
# kept (its value can't be read back), otherwise git config user.email is used. tf-05's catchup
# runs this script before it dispatches the workflow whenever the workflow references
# BUDGET_EMAIL. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
if [[ "$(gh api "repos/$repo/actions/secrets/BUDGET_EMAIL" --jq .name 2>/dev/null || true)" == BUDGET_EMAIL ]]; then
  echo "tf-12: kept the repo secret BUDGET_EMAIL"
  exit 0
fi

email="$(git config user.email || true)"
if [[ -z "$email" ]]; then
  echo "tf-12: git config user.email is not set. Set the budget alert address yourself:" >&2
  echo "  gh secret set BUDGET_EMAIL -R $repo --body <your email>" >&2
  exit 1
fi
if [[ "$email" == *@users.noreply.github.com ]]; then
  echo "tf-12: warning: $email is a GitHub noreply address; budget alerts sent there are lost." >&2
  echo "  Change it: gh secret set BUDGET_EMAIL -R $repo --body <your email>" >&2
fi
gh secret set BUDGET_EMAIL -R "$repo" --body "$email"
echo "tf-12: set the repo secret BUDGET_EMAIL"
