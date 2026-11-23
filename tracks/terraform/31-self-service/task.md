---
id: tf-31
title: Self-service team onboarding
target_minutes: 20
requires: [tf-30]
---
# tf-31 Self-service team onboarding

The payments team wants to ship their own service on the platform, and they shouldn't need a
platform engineer for every resource. What they need is always the same: a resource group with a
budget, and an identity their repo's pipeline can deploy with, allowed to touch their group and
nothing else. You turn that into one module, so onboarding the next team is one module call and
a pull request.

`./lab.sh next` saved starters in `~/.platform-lab/starter/tf-31/`:

- `team-env/`: the module's `versions.tf`, `variables.tf`, `outputs.tf`, tests and a README
  skeleton. You write `main.tf`. Copy: `cp -rn ~/.platform-lab/starter/tf-31/team-env "$MODULES_DIR/"`
- `live/terraform/teams/payments/`: the stack's `versions.tf` and `variables.tf`; you write the
  module call.
- `live/terraform/bootstrap/team-onboarding.tf`: CI may hand out `Contributor`, to managed
  identities only (read the comment; its first RBAC condition never allowed that).
  Copy both: `cp -rn ~/.platform-lab/starter/tf-31/live/terraform/. "$LIVE_DIR/terraform/"`

The plan called the team repo `payments-app`; the lab names it `{{PREFIX}}-payments-app`, so two
learners' labs under one GitHub owner never collide.

## Deliverables

- [ ] The team's repo exists, public and empty:
      `gh repo create {{GH_OWNER}}/{{PREFIX}}-payments-app --public --description "Payments team"`.
- [ ] `terraform/bootstrap` with `team-onboarding.tf`, applied locally (`terraform apply`).
- [ ] **Modules repo:** `team-env/main.tf`, so that `terraform test` passes:
  - a resource group named rg-*prefix*-*team* (for payments: `rg-{{PREFIX}}-payments`) with the
    tags `owner`, `env`, `managed_by = "terraform"` and `team`
  - an identity id-*prefix*-*team*-ci in it (`id-{{PREFIX}}-payments-ci`), with one federated
    credential `gh-main` for pushes to the team repo's `main` branch. Build the subject the way
    bootstrap does for your own repo (tf-04): `repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main`,
    IDs from GitHub's API
  - `Contributor` for that identity on the team's resource group only
  - a monthly budget budget-*prefix*-*team* (`budget-{{PREFIX}}-payments`) on the group: alerts at
    80 % actual and 100 % forecast to `var.budget_contact_emails`

  Generate the README section, add a `3.1.0` changelog entry and the README row; CI green, tag
  `v3.1.0`.
- [ ] **Platform repo, one PR:** a new stack `terraform/teams/payments` (backend key
      `teams-payments.tfstate`, already in `STACK_ORDER`) with exactly one `module "team_payments"`
      call (`team-env?ref=v3.1.0`, `budget_amount = 100`). It creates `rg-{{PREFIX}}-payments`,
      `id-{{PREFIX}}-payments-ci` and `budget-{{PREFIX}}-payments`. Also:
  - its `.terraform.lock.hcl` for both platforms (tf-30), and a line in `dependabot.yml`
  - `TF_VAR_github_token: ${{ github.token }}` in the `env` of `terraform.yml` and `drift.yml`:
    the module's GitHub API lookup then doesn't count against the anonymous rate limit
- [ ] Merge; the pipeline applies.

## Done when

`az identity federated-credential list -g rg-{{PREFIX}}-payments --identity-name id-{{PREFIX}}-payments-ci -o table`
shows one credential for `{{PREFIX}}-payments-app`'s main branch, the identity holds `Contributor`
on `rg-{{PREFIX}}-payments` and nothing else, and `./lab.sh grade` passes.

Target: 20 minutes.
