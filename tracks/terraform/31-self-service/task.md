---
id: tf-31
title: Self-service team onboarding
target_minutes: 30
requires: [tf-30]
---
# tf-31 Self-service team onboarding

The payments team wants to ship their own service on the platform, and they shouldn't need a
platform engineer for every resource. What they need is always the same: a place of their own
with a budget, and an identity their repo's pipeline can deploy with, allowed to touch that place
and nothing else.

The split that makes this safe: **the platform vends a scoped landing spot, the team operates
inside it.** You, the subscription owner, create the team's resource group in bootstrap and allow
the pipeline to grant `Contributor` *in that group only*. The pipeline then onboards the team with
one module call: identity, federated credential, budget and the team's `Contributor` role, all
inside the vended group. However the module or a later PR goes wrong, CI can't hand out
`Contributor` anywhere else.

This task gets 30 minutes: a vending step in bootstrap, a new module and its release, a new stack,
and the team's repo.

`./lab.sh next` saved starters in `~/.platform-lab/starter/tf-31/`:

- `team-env/`: the module's `versions.tf`, `variables.tf`, `outputs.tf`, tests, a README skeleton
  and a `main.tf` skeleton with `TODO(tf-31)` blocks. Copy:
  `cp -rn ~/.platform-lab/starter/tf-31/team-env "$MODULES_DIR/"`
- `live/terraform/bootstrap/team-vending.tf`: the vending (read it: the group, and an RBAC
  Administrator assignment for CI on that group, limited to `Contributor` for service principals).
- `live/terraform/teams/payments/`: the stack's `versions.tf` and `variables.tf`; you write the
  module call. Copy both: `cp -rn ~/.platform-lab/starter/tf-31/live/terraform/. "$LIVE_DIR/terraform/"`

The plan called the team repo `payments-app`; the lab names it `{{PREFIX}}-payments-app`, so two
learners' labs under one GitHub owner never collide.

## Deliverables

- [ ] The team's repo exists, public and empty:
      `gh repo create {{GH_OWNER}}/{{PREFIX}}-payments-app --public --description "Payments team"`.
- [ ] **Vend:** `terraform/bootstrap` with `team-vending.tf`, applied locally (`terraform apply`):
      `rg-{{PREFIX}}-payments` (tags `owner`, `env = "dev"`, `managed_by`, `team`) and CI's
      scoped RBAC Administrator assignment on it.
- [ ] **Modules repo:** fill in the `TODO(tf-31)` blocks of `team-env/main.tf` so that
      `terraform test` passes. The module reads the vended group (`var.resource_group_name`) and
      never creates one. Inside it:
  - an identity id-*prefix*-*team*-ci (`id-{{PREFIX}}-payments-ci`) with one federated credential
    `gh-main` for pushes to the team repo's `main` branch. Build the subject the way bootstrap
    does for your own repo (tf-04): `repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main`, IDs
    from GitHub's API
  - `Contributor` for that identity on the vended group
  - a monthly budget budget-*prefix*-*team* (`budget-{{PREFIX}}-payments`) on the group: alerts
    at 80 % actual and 100 % forecast to `var.budget_contact_emails`

  Generate the README section, add a `3.1.0` changelog entry and the README row; CI green, tag
  `v3.1.0`.
- [ ] **Platform repo, one PR:** a new stack `terraform/teams/payments` (backend key
      `teams-payments.tfstate`, already in `STACK_ORDER`) with exactly one `module "team_payments"`
      call (`team-env?ref=v3.1.0`, the vended `rg-{{PREFIX}}-payments` as `resource_group_name`,
      `budget_amount = 100`). Also:
  - its `.terraform.lock.hcl` for both platforms (tf-30), and a line in `dependabot.yml`
  - `TF_VAR_github_token: ${{ github.token }}` in the `env` of the Terraform steps (plan and
    apply in `terraform.yml`, plan in `drift.yml`): the module's GitHub API lookup then doesn't
    count against the anonymous rate limit, and no other step sees the token
- [ ] Merge; the pipeline applies.

## Done when

`az identity federated-credential list -g rg-{{PREFIX}}-payments --identity-name id-{{PREFIX}}-payments-ci -o table`
shows one credential for `{{PREFIX}}-payments-app`'s main branch, the identity holds `Contributor`
on `rg-{{PREFIX}}-payments` and nothing else, CI can't grant `Contributor` at subscription scope,
and `./lab.sh grade` passes.

Target: 30 minutes.
