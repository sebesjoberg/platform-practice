---
id: tf-24
title: Prod, gated
target_minutes: 25
requires: [tf-23]
---
# tf-24 Prod, gated

Dev has run on spoke `v2.0.0` and app-env `v2.1.0` without surprises. The CTO signs off on
prod, under two conditions: prod is built from the same module releases as dev, and nothing
reaches prod without a human approving that exact run. The `prod` environment from tf-06 and
the `gh-env-prod` credential from tf-04 have waited for this.

This task gets 25 minutes: a stack change and a pipeline change, and the first approval.

## Deliverables

- [ ] `terraform/env-prod`, from the same releases as env-dev:
  - spoke on `?ref=v2.0.0` with `vnet_cidr` (completing the canary of tf-20)
  - `module "app_env"` from `//app-env?ref=v2.1.0` with the secret
    `greeting = "Hello from {{PREFIX}} prod"`: `id-{{PREFIX}}-app-prod`,
    `kv-{{PREFIX}}-prod-{{SUFFIX}}`, `pe-kv-{{PREFIX}}-prod`
  - `AcrPull` for `id-{{PREFIX}}-app-prod` on `acr{{PREFIX}}{{SUFFIX}}`
  - variable `suffix`, the `key_vault` provider feature and the `time` pin, as in env-dev
  - no container app in prod yet: the product team goes live later
- [ ] The workflow:
  - job `apply` applies every selected stack **except** `env-prod`, and tells the next job
    whether `env-prod` was selected (a job output)
  - a third job `apply-prod`: `needs: apply`, runs only when `env-prod` was selected,
    `environment: prod`, applies `terraform/env-prod`. Its own concurrency group, so a run
    waiting for approval doesn't block dev applies.
  - `plan` stays as it is: it plans every stack, env-prod included, and needs no other job
- [ ] One PR. Merge it, watch `apply` finish, then approve `apply-prod` (Actions tab,
      **Review deployments**).

## Done when

`gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/deployments?environment=prod --jq '.[0].id'` prints a
deployment whose status is `success`, both vaults exist, and `./lab.sh grade` passes.

From now on `./lab.sh resume` also waits for your approval before it rebuilds prod.

Target: 25 minutes.
