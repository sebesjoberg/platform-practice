# tf-06 solution

## Approach

Two GitHub settings, made through the API so you can repeat them (the UI works too):
a ruleset on `main`, and a `prod` environment with you as required reviewer.

## Ruleset

```bash
repo={{GH_OWNER}}/{{LIVE_REPO}}
cat > /tmp/protect-main.json <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "bypass_actors": [
    { "actor_type": "RepositoryRole", "actor_id": 5, "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "plan" } ]
      } }
  ]
}
JSON
gh api -X POST "repos/$repo/rulesets" --input /tmp/protect-main.json
# later changes: gh api -X PUT "repos/$repo/rulesets/<id>" --input /tmp/protect-main.json
```

### Why the admin bypass?

`./lab.sh catchup` replaces `main` with a reference state and force-pushes it (with a lease,
after backing your work up to `my-work/<timestamp>`). Without a bypass, the ruleset blocks
force pushes for everyone, catchup included. `actor_id: 5` is the built-in **Repository
admin** role. You own the repo, so you hold it.

The trade-off: as admin you *can* still push straight to `main`. GitHub then prints "Bypassed
rule violations" and records the bypass. Don't do it outside catchup. In a team you'd give
the bypass to a dedicated automation identity, not a human role, or use `pull_request`
mode.

## Environment `prod`

```bash
uid=$(gh api users/{{GH_OWNER}} --jq .id)
gh api -X PUT "repos/$repo/environments/prod" --input - <<JSON
{ "reviewers": [ { "type": "User", "id": $uid } ], "prevent_self_review": false }
JSON
```

Nothing deploys to `prod` yet. Once a job declares `environment: prod`, it waits for your
approval, and it logs in to Azure with the `gh-env-prod` federated credential from tf-04.

## Verify

```bash
gh api repos/$repo/rules/branches/main --jq '.[].type'     # deletion non_fast_forward pull_request required_status_checks
gh api repos/$repo/environments/prod --jq '.protection_rules[].reviewers[].reviewer.login'
gh pr create --fill && gh pr checks --watch   # merge is allowed once "plan" is green
./lab.sh grade
```

## Cost

Free.
