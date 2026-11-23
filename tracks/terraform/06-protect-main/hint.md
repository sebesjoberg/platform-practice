# tf-06 hints

Docs:
- About rulesets and the available rules: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
- Rulesets REST API (create, update, `bypass_actors`): https://docs.github.com/rest/repos/rules
- Deployment environments and required reviewers: https://docs.github.com/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments

Traps:
- **The check must have run at least once** before the UI offers it in the "required status
  checks" picker. It's the job name from tf-05: `plan`, not `terraform / plan`.
- **Required approvals > 0 locks a solo engineer out.** GitHub never lets you approve your own
  PR. Use 0 approvals; the required `plan` check is the real gate.
- **Bypass list.** In the API the admin role is `{"actor_type": "RepositoryRole",
  "actor_id": 5, "bypass_mode": "always"}`. With mode `pull_request` the bypass only works
  through PRs, so the force-push from `./lab.sh catchup` would be rejected.
- **A required check that never reports blocks the PR forever.** The `plan` job must run on
  every PR to `main`. Don't add `paths:` filters to the `pull_request` trigger.
- **Required reviewers need the numeric user ID** in the API
  (`gh api users/{{GH_OWNER}} --jq .id`). The settings page takes your login. Leave "Prevent
  self-review" off, or you can never approve your own deployments.
- Rulesets and environment reviewers are available for public repos on GitHub Free.
