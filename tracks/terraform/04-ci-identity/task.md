---
id: tf-04
title: CI identity
target_minutes: 20
requires: [tf-03]
---
# tf-04 CI identity

Soon GitHub Actions will run Terraform for you. The security team has two rules: **no
long-lived secrets** and **least privilege**. Your tenant doesn't let you create app
registrations anyway, so CI gets a user-assigned managed identity that trusts GitHub's OIDC
tokens.

The identity is part of the `bootstrap` stack. You apply it from your machine; the pipeline
never manages its own identity.

## Deliverables

In `terraform/bootstrap`:

- [ ] User-assigned managed identity `id-{{PREFIX}}-github-ci` in `rg-{{PREFIX}}-tfstate`
      (`{{LOCATION}}`, same tags as the group).
- [ ] Three federated identity credentials on it. All use issuer
      `https://token.actions.githubusercontent.com` and audience `api://AzureADTokenExchange`:

  | Name | Subject |
  |---|---|
  | `gh-main` | `<prefix>:ref:refs/heads/main` |
  | `gh-pr` | `<prefix>:pull_request` |
  | `gh-env-prod` | `<prefix>:environment:prod` |

  `<prefix>` is your repo's OIDC subject prefix. New repos use the immutable format
  `repo:{{GH_OWNER}}@<owner id>/{{LIVE_REPO}}@<repo id>`. Read yours with
  `gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/actions/oidc/customization/sub --jq .sub_claim_prefix`.
- [ ] Role assignments for the identity:
  - `Contributor` on the subscription
  - `Role Based Access Control Administrator` on the subscription, with a condition
    (version `2.0`). The condition allows creating and deleting assignments of exactly
    these built-in roles and nothing else: `AcrPull`, `Key Vault Secrets User`, `Reader`,
    `Storage Blob Data Contributor`.
  - `Storage Blob Data Contributor` on the `tfstate` **container** (not the whole account)
- [ ] Applied locally (`terraform apply` in `terraform/bootstrap`). Committed and pushed to
      `main`.

## Done when

`az identity federated-credential list -g rg-{{PREFIX}}-tfstate --identity-name id-{{PREFIX}}-github-ci -o table`
shows the three credentials, `az role assignment list --assignee <principal id> --all -o table`
shows the three roles, and `./lab.sh grade` passes.

Target: 20 minutes.
