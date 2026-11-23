#!/usr/bin/env bash
# tf-30 catchup (after-push, cwd = LIVE_DIR):
#   - the Dependabot secrets BUDGET_EMAIL and LEARNER_IP. Dependabot PRs run without the repo's
#     Actions secrets; without these their plan fails the variable validation. An existing
#     secret is kept (a value can't be read back); otherwise BUDGET_EMAIL comes from
#     git config user.email (as tf-12's catchup does) and LEARNER_IP from the lab config.
#   - tag v3.0.0 at tf-30's reference modules tree (normally done already by tf-05's hook, which
#     creates every pinned tag before the pipeline runs; see lib/modules-tag.sh).
# tf-04's hook has applied bootstrap with the new provider. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
have="$(gh api "repos/$repo/dependabot/secrets?per_page=100" --jq '.secrets[].name' 2>/dev/null || true)"
if grep -qx BUDGET_EMAIL <<<"$have"; then
  echo "tf-30: kept the Dependabot secret BUDGET_EMAIL"
else
  email="$(git config user.email || true)"
  [[ -n "$email" ]] || {
    echo "tf-30: git config user.email is not set; run: gh secret set --app dependabot BUDGET_EMAIL -R $repo --body <your email>" >&2
    exit 1
  }
  gh secret set --app dependabot BUDGET_EMAIL -R "$repo" --body "$email"
  echo "tf-30: set the Dependabot secret BUDGET_EMAIL"
fi
if grep -qx LEARNER_IP <<<"$have"; then
  echo "tf-30: kept the Dependabot secret LEARNER_IP"
else
  [[ -n "${LEARNER_IP:-}" ]] || { echo "tf-30: LEARNER_IP is not set; run ./lab.sh init --refresh-ip" >&2; exit 1; }
  gh secret set --app dependabot LEARNER_IP -R "$repo" --body "$LEARNER_IP"
  echo "tf-30: set the Dependabot secret LEARNER_IP"
fi

if [[ "${CATCHUP_PHASE:-}" == after-push && -d "${MODULES_DIR:-}/.git" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
  modules_tag v3.0.0
fi
