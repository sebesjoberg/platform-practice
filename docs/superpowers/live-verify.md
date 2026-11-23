# Live-verification checklist (for Task 16 selftest against Azure/GitHub)

Things the offline gate cannot prove. Check each during the live selftest; fix and tick.

## Terraform phase 0 (tf-01…tf-06)
- [ ] OIDC immutable subjects: GET `repos/{o}/{r}/actions/oidc/customization/sub` returns `sub_claim_prefix`; API-built prefix equals it byte-for-byte; PUT `use_immutable_subject` accepted; PR/main/environment tokens match `gh-pr`/`gh-main`/`gh-env-prod`.
- [ ] tf-02 first apply with shared key disabled: no 403 / KeyBasedAuthenticationNotPermitted; second plan clean.
- [ ] ABAC condition heredoc: no perpetual diff (ForceNew) after apply.
- [ ] Container role scope id equals check's `.../blobServices/default/containers/tfstate`.
- [ ] tf-01 empty-repo clone branch name; `gh auth setup-git` over HTTPS.
- [ ] Versions: Terraform 1.17.x resolves; azurerm 4.81 latest 4.x; actions/checkout@v4, hashicorp/setup-terraform@v3, azure/login@v2 still supported; azure/login with user-assigned MI.
- [ ] `gh pr comment` works with GITHUB_TOKEN + `pull-requests: write`; author github-actions[bot].
- [ ] Ruleset REST shape accepted with not-yet-run required check; RepositoryRole 5 bypass works for personal-repo owner incl. leased force-push; `rules/branches/main` returns `required_approving_review_count`.
- [ ] gh output shapes: ruleset GET includes bypass_actors; environment GET `protection_rules[].reviewers[].reviewer.login`.
- [ ] az output shapes: `role assignment list --all` condition/conditionVersion/scope casing; `blob-service-properties show` fields; `container-rm show` publicAccess None; `az storage blob exists --auth-mode login`.
- [ ] tf-02 role check when az is logged in as a service principal (`az ad signed-in-user show` fails).
- [ ] Catchup timing: retry budgets (tf-03 10×30s, tf-04 5×30s, tf-05 3 runs); concurrency group cancelling a pending dispatched run; run-id detection.
- [ ] Stack discovery ordering matches STACK_ORDER once several stacks exist (tf-14).
- [ ] Standard_B2ats_v2 availability/quota in swedencentral; 1 GiB RAM enough for the runner VM.
- [ ] `data "http"` to api.github.com unauthenticated rate limit from the learner's network.
- [ ] tf-05 setup.sh starter flow in a real clone; plan-comment truncation with a large real plan; default branch of a repo created by `gh repo create`.
