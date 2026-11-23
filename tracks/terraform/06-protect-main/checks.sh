# tf-06 checks (sourced by the grader; cwd = LIVE_DIR)
# no check_code: rulesets and environments are GitHub settings, not files in the repo.

export TF06_REPO="$GH_OWNER/$LIVE_REPO"
export TF06_RULES_JQ='any(.[]; .type == "pull_request") and any(.[]; .type == "non_fast_forward") and any(.[]; .type == "deletion")'
export TF06_PLAN_JQ='any(.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?; .context == "plan")'
export TF06_APPROVALS_JQ='all(.[] | select(.type == "pull_request"); .parameters.required_approving_review_count == 0)'
export TF06_BYPASS_JQ='select(.enforcement == "active" and any(.bypass_actors[]?; .actor_type == "RepositoryRole" and .actor_id == 5 and .bypass_mode == "always")) | .id'
export TF06_REVIEWER_JQ='any(.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]? | .reviewer.login // ""; ascii_downcase == (env.GH_OWNER | ascii_downcase))'

check "main requires a PR and blocks force pushes and deletion" \
  'gh api "repos/$TF06_REPO/rules/branches/main" | jq -e "$TF06_RULES_JQ"' \
  "rules on main must include pull_request, non_fast_forward and deletion (active ruleset)"

check "main requires the status check plan" \
  'gh api "repos/$TF06_REPO/rules/branches/main" | jq -e "$TF06_PLAN_JQ"' \
  "rules on main must require the status check \"plan\""

check "the PR rule needs 0 approvals" \
  'gh api "repos/$TF06_REPO/rules/branches/main" | jq -e "$TF06_APPROVALS_JQ"' \
  "set required approvals to 0: you can't approve your own PRs"

check "an active ruleset lets the Repository admin role bypass (always)" \
  'ids="$(gh api "repos/$TF06_REPO/rulesets" --jq ".[] | select(.target == \"branch\") | .id")" && for i in $ids; do gh api "repos/$TF06_REPO/rulesets/$i" | jq "$TF06_BYPASS_JQ"; done | grep -q .' \
  "add bypass actor RepositoryRole 5 (admin) with bypass_mode always, or ./lab.sh catchup can't force-push main"

check "environment prod has $GH_OWNER as required reviewer" \
  'gh api "repos/$TF06_REPO/environments/prod" | jq -e "$TF06_REVIEWER_JQ"' \
  "environment prod needs a required reviewer rule with $GH_OWNER"
