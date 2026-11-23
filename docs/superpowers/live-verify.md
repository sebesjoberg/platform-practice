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

## Terraform phase 1 (tf-07…tf-14)
- [ ] tf-07: the refactor PR plans `No changes.` for landing-zone (tags/name/location unchanged).
- [ ] tf-08/09: `az network vnet subnet list` returns `addressPrefix` for single-prefix subnets created with `address_prefixes` (checks fall back to `addressPrefixes[0]`); `delegations[].serviceName`; `networkSecurityGroup.id` casing.
- [ ] tf-09: `snet-aca` delegation with `actions = [".../subnets/join/action"]` gives no perpetual diff; all four peerings reach `Connected` in one apply.
- [ ] tf-10: link output shape (`virtualNetwork.id`, `registrationEnabled`); zones/links accept no location (global).
- [ ] tf-11: CI apply works with Resource Policy Contributor (fresh-assignment propagation within tf-05's 3 retries); the probe's error text contains `RequestDisallowedByPolicy`; enforcement delay vs. tf-11 catchup's 30-minute wait; `az policy assignment show --scope` shape (`parameters.listOfAllowedLocations.value`, `policyDefinitionId` casing); built-in e56962a6… still exempts `global`.
- [ ] tf-11: the `rg-*` scope of the owner-tag policy leaves Azure-created groups alone (`NetworkWatcherRG` now; the Container Apps infrastructure group `ME_…` in tf-23). Later setup.sh scripts that create `rg-*` groups (tf-26 `rg-{P}-legacy`, tf-31) must pass `--tags owner=…`.
- [ ] tf-12: **budgets on the Visual Studio offer.** If `azurerm_consumption_budget_subscription` fails as unsupported, apply solution.md's fallback and decide what the budget check does on that offer.
- [ ] tf-12: Consumption REST `api-version=2021-10-01` shape (`properties.amount`, `timeGrain`, `notifications{}.threshold/thresholdType/contactGroups`); action group `emailReceivers[].emailAddress`; `gh variable get` available in the installed gh; `plantimestamp()` start date accepted and `ignore_changes` keeps later plans clean; the PR plan comment shows `(sensitive value)`, not the address.
- [ ] tf-12 catchup: tf-05's hook runs `12-budget/catchup.sh` before dispatching when the workflow references `BUDGET_EMAIL`; a noreply `git config user.email` prints the warning.
- [ ] `./lab.sh nuke` destroys landing-zone with the placeholder `TF_VAR_budget_email`.
- [ ] tf-13: `daily_quota_gb = 0.1` accepted; `az monitor log-analytics workspace show` has `workspaceCapping.dailyQuotaGb`; `az monitor diagnostic-settings subscription list` shape (`value` wrapper or plain list; `workspaceId` casing); the eight `enabled_log` categories plan clean after apply.
- [ ] tf-14 PR 1: import IDs from solution.md accepted (NSG association = subnet ID; peering and DNS-link IDs); env plans show `15 to import, 0 to add, 0 to change, 0 to destroy`; landing-zone shows only "no longer be managed"; one apply run (landing-zone, env-dev, env-prod in that order) succeeds; PR 2 plans `No changes.` everywhere.
- [ ] tf-14 setup.sh snapshot: `az network vnet show` includes `subnets[].id` and `virtualNetworkPeerings[].id`; `az resource show --ids <many>` handles child resources (subnets, peerings, `privateDnsZones/virtualNetworkLinks`) and returns an array; `az storage blob download --auth-mode login -f <file> --no-progress` works for the state check.
- [ ] tf-14 limitation: Azure resource IDs are derived from names, so the snapshot check proves "still there under the same ID", not "never recreated". `catchup tf-14` from a tf-13 state has no import blocks in the reference: landing-zone destroys the spokes, the env stacks recreate them (same IDs). Confirm the live selftest passes that way and that resume after pause rebuilds env-dev/env-prod (data sources need the hub, which pause keeps).

## Reviewer notes, phase 1 (tf-07…tf-14)
- [ ] tf-14 PR 1: env plans show only imports (0 change: tags, delegation actions); landing-zone plan shows only "no longer managed"; PR 2 no changes.
- [ ] tf-12 budget on Visual Studio Professional offer; Consumption REST shape; plantimestamp start date; clean later plans; PR comment shows (sensitive value).
- [ ] tf-11: Resource Policy Contributor propagation within tf-05 retries; probe error text and enforcement delay; `az policy assignment show` shape; a policy written with "Deny" passes.
- [ ] Owner-tag policy doesn't block NetworkWatcherRG / ME_* Container Apps RG; later setup scripts creating rg-* (tf-26 legacy, tf-31) pass owner/env/managed_by tags.
- [ ] tf-08/09/10 shapes: subnet addressPrefix vs addressPrefixes; delegation actions diff; peerings Connected; link virtualNetwork.id / registrationEnabled.
- [ ] tf-13: daily_quota_gb 0.1 accepted; workspaceCapping.dailyQuotaGb; diag list shape; 8 categories plan clean.
- [ ] tf-05 catchup chaining to tf-12 (noreply email warning); `./lab.sh nuke` with placeholder budget email.
- [ ] `az storage blob download --auth-mode login` permission for the learner (tf-14 state check).
- [ ] tf-14 (fix round 1): the ID check and the guid check each run tf14_collect (9 az calls: group show, vnet show, nsg list per env; hub peering list; DNS link list per zone): measure that each stays well inside the 60 s check timeout; the JMESPath filters (`[?name=='peer-hub-to-dev' || ...]`, `[?name=='link-vnet-…']`) return the IDs; `az network vnet show` returns `resourceGuid`.
- [ ] tf-14 guid baseline across catchup: setup writes `$LAB_HOME/snapshots/tf-14.guids`; the live selftest (setup → grade fails → catchup recreates the spokes → tf-14's catchup deletes the guid file → grade) passes; a learner's PR 1 apply keeps the guids (check passes); pause/resume between PR 1 and grading changes them and the check fails with the "recreated" reason, and `./lab.sh catchup tf-14` clears it.
- [ ] tf-12 catchup reads the variable with `gh api repos/{o}/{r}/actions/variables/BUDGET_EMAIL` (404 when missing is treated as unset); works with Ubuntu's apt gh 2.45.
