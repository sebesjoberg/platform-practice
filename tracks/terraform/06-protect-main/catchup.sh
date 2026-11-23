#!/usr/bin/env bash
# tf-06 catchup (after-push): ruleset protect-main on main (admin bypass so catchup can still
# force-push) and environment prod with GH_OWNER as required reviewer. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"

ruleset='{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "bypass_actors": [ { "actor_type": "RepositoryRole", "actor_id": 5, "bypass_mode": "always" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "plan" } ] } }
  ]
}'

id="$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "protect-main") | .id' | head -n 1)"
if [[ -n "$id" ]]; then
  gh api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$ruleset" >/dev/null
else
  gh api -X POST "repos/$repo/rulesets" --input - <<<"$ruleset" >/dev/null
fi

uid="$(gh api "users/$GH_OWNER" --jq .id)"
gh api -X PUT "repos/$repo/environments/prod" --input - >/dev/null <<JSON
{ "reviewers": [ { "type": "User", "id": $uid } ], "prevent_self_review": false }
JSON
echo "tf-06: ruleset protect-main and environment prod are in place"
