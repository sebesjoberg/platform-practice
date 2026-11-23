#!/usr/bin/env bash
# tf-31 catchup (cwd = LIVE_DIR):
#   - the payments team's repo <prefix>-payments-app: public and empty, created if missing. The
#     team-env module looks it up in GitHub's API at plan time, so tf-05's catchup runs this before
#     it dispatches the pipeline whenever terraform/teams/payments exists. Like tf-04, it opts the
#     repo in to immutable OIDC subjects if GitHub reports a legacy (name-only) prefix: the module
#     builds the immutable one.
#   - tag v3.1.0 at tf-31's reference modules tree (after-push; normally done already by tf-05's
#     hook, which creates every pinned tag before the pipeline runs).
# tf-04's hook has applied bootstrap first, which vends rg-<prefix>-payments and CI's scoped RBAC
# Administrator assignment (team-vending.tf): the stack works inside that group. Idempotent.
set -euo pipefail

repo="${GH_OWNER:?}/${PREFIX:?}-payments-app"
if gh repo view "$repo" --json name >/dev/null 2>&1; then
  echo "tf-31: kept the team repo $repo"
else
  gh repo create "$repo" --public --description "Payments team's service (platform lab, tf-31)" >/dev/null
  echo "tf-31: created the team repo $repo"
fi
if sub="$(gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null)" &&
  [[ -n "$sub" && "$sub" != *@* ]]; then
  gh api -X PUT "repos/$repo/actions/oidc/customization/sub" -F use_default=true -F use_immutable_subject=true >/dev/null ||
    echo "tf-31: could not opt $repo in to immutable subjects; the module builds the immutable one" >&2
fi

if [[ "${CATCHUP_PHASE:-}" == after-push && -d "${MODULES_DIR:-}/.git" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
  modules_tag v3.1.0
fi
