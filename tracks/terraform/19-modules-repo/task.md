---
id: tf-19
title: A versioned modules repo
target_minutes: 25
requires: [tf-18]
catchup_creates_repo: modules
---
# tf-19 A versioned modules repo

The payments team wants a spoke too, and they don't get write access to the platform repo. The
CTO wants the module in its own repo, released with version tags, and every stack (ours
included) pinned to a release. A merge to the module must never change a stack by surprise.

This task gets 25 minutes: a new repo with its own CI, a first release, and the switch of both
env stacks in one pull request.

## Deliverables

- [ ] A **public** GitHub repo `{{GH_OWNER}}/{{MODULES_REPO}}` with default branch `main`,
      cloned to the `MODULES_DIR` path from `config.env` (default `~/acme/{{MODULES_REPO}}`).
- [ ] In it:
  - the module at `spoke/`: everything from `terraform/modules/spoke`, including `tests/` and
    `README.md` (update the usage example to the new source)
  - a root `README.md` that lists the modules and says how to pin a version
  - a `.gitignore` for `.terraform/`, state files and `.terraform.lock.hcl`
  - `.tflint.hcl`, copied from the platform repo
  - `.github/workflows/ci.yml`: `./lab.sh next` saved a ready one in
    `~/.platform-lab/starter/tf-19/ci.yml` (fmt, validate, `terraform test`, tflint, trivy)
- [ ] CI green on `main`, then an annotated tag `v1.0.0` on that commit, pushed.
- [ ] In `{{LIVE_REPO}}`: both env stacks use
      `source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v1.0.0"`,
      `terraform/modules/spoke` is deleted, and no `source = "../modules/…"` is left. One PR;
      both env stacks plan `No changes.` Merge it.

## Done when

`./lab.sh grade` passes: the module, its tests and CI are in the modules repo, which is public
with tag `v1.0.0`, the env stacks pin it, nothing local is left, and the run on `main` is green.

Target: 25 minutes.
