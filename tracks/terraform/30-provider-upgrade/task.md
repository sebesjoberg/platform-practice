---
id: tf-30
title: Provider upgrade
target_minutes: 35
requires: [tf-29]
---
# tf-30 Provider upgrade

The platform runs on azurerm 4.x, and 5.x has been out for months. Staying behind gets more
expensive every week: fixes and new resources only land in 5.x, and the longer you wait, the
bigger the jump. You upgrade now, deliberately, through the modules repo and a pull request, and
you set things up so that the next upgrade comes to you as a pull request instead of a surprise.

This task gets 35 minutes: a provider major touches every stack and every module, needs a module
release before the platform PR, waits for a prod approval, and ends with a local bootstrap apply.

`./lab.sh next` saved starters in `~/.platform-lab/starter/tf-30/`: each stack's `versions.tf`
and each module's `versions.tf` with the new pins and the resource-provider lists 5.x needs, and
each stack's `.terraform.lock.hcl`, already locked for both platforms with
`terraform providers lock -platform=linux_amd64 -platform=windows_amd64` (that would otherwise
download azurerm twice per stack). They are the mechanical part. Diff them against yours before
you copy: `diff -r ~/.platform-lab/starter/tf-30/live/terraform "$LIVE_DIR/terraform"`.

## Deliverables

- [ ] Read the [5.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide)
      and list what hits *this* code. The provider-level changes hit every stack; at least one
      resource change hits the landing zone and the spoke module.
- [ ] **Modules repo:** every module requires azurerm `>= 5.14, < 6.0`; fix what 5.0 broke in
      `spoke` (tests included), regenerate the READMEs, add a `3.0.0` entry to `CHANGELOG.md`
      that tells callers what to change. CI green, tag **`v3.0.0`**: a provider major is a
      breaking change for every caller, even where the module's own code didn't change.
- [ ] **Platform repo, one PR:**
  - every stack (`bootstrap` too) pins azurerm `~> 5.14` and fixes its own breaking changes
  - every module source moves to `?ref=v3.0.0`
  - each stack commits a `.terraform.lock.hcl` with hashes for `linux_amd64` (CI, WSL) and
    `windows_amd64` (the starter's; `terraform init` in each stack verifies it, and tf-31 has you
    lock a new stack yourself)
  - `.github/dependabot.yml`: the `terraform` ecosystem for every stack directory (providers and
    module refs), and `github-actions` for the workflows
  - the plan comment says `No changes.` for every stack. Anything else, and above all any
    `forces replacement`, means stop and read again: the Ansible track's VMs, vaults and jump
    host must not be recreated.
- [ ] Dependabot PRs run without your repo's secrets. Give it its own copies:

  ```bash
  gh secret set --app dependabot BUDGET_EMAIL -R {{GH_OWNER}}/{{LIVE_REPO}} --body <your email>
  gh secret set --app dependabot LEARNER_IP -R {{GH_OWNER}}/{{LIVE_REPO}} --body {{LEARNER_IP}}
  ```

- [ ] Merge, let the pipeline apply (approve `apply-prod`), then apply `terraform/bootstrap`
      locally with the new provider: `terraform init -upgrade && terraform apply` shows no
      changes.

## Done when

The newest pipeline run on `main` is green, tag `v3.0.0` exists, Dependabot has its two secrets,
and `./lab.sh grade` passes. Within a week Dependabot opens its first PR; read its plan comment
like any other.
