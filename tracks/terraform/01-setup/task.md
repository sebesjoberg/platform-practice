---
id: tf-01
title: Setting up
target_minutes: 20
requires: []
catchup_creates_repo: live
---
# tf-01 Setting up

Welcome to Acme. The CTO wants the platform built the GitOps way from day one: every
piece of infrastructure lives in Git and nobody clicks in the portal. Before you write
any Terraform, get your workstation and the platform repo ready.

Everything runs in **WSL Ubuntu**, not in Windows. Use the Linux builds of every tool.
A Windows `az` or `terraform` under `/mnt/c/...` on your PATH does not count.

> Reading this before `./lab.sh init`? Then the names below still show placeholders in double
> curly braces. Once init has run, `./lab.sh next` starts the clock and shows your own names.

## Deliverables

- [ ] Linux tools in WSL: `terraform` 1.17 or newer, `az`, `gh`, `git` and `jq`.
      (`tflint`, `trivy` and `terraform-docs` are used later; you can install them now.)
- [ ] `az login`, then `az account set --subscription <your Visual Studio subscription>`.
- [ ] `gh auth login` (HTTPS, and let gh act as your git credential helper).
- [ ] `./lab.sh init` has written `~/.platform-lab/config.env`. It records your prefix
      (`{{PREFIX}}`), the random suffix (`{{SUFFIX}}`), your subscription and the repo names.
- [ ] A **public** GitHub repo `{{GH_OWNER}}/{{LIVE_REPO}}`, cloned to the `LIVE_DIR` path from
      `config.env` (default `~/acme/{{LIVE_REPO}}`). `./lab.sh init` offers to create and clone
      it for you; say yes, or do it yourself with `gh repo create`.
- [ ] A `.gitignore` at the root of the repo that ignores:
  - every `.terraform/` directory, at any depth
  - every state file and state backup (`*.tfstate`, `*.tfstate.*`)
  - every `*.tfvars` file
  It must **not** ignore `*.auto.tfvars.example` files or `.terraform.lock.hcl`. You commit
  lock files later in the lab.
- [ ] Your default branch must be `main` (locally and on GitHub). The `.gitignore` is committed
      on `main` and pushed to GitHub.

## Done when

`terraform version` and `az account show` work from WSL and show the right subscription,
`gh repo view {{GH_OWNER}}/{{LIVE_REPO}}` shows a public repo, and `./lab.sh grade` passes.
