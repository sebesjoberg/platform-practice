---
id: tf-18
title: Lint and scan in CI
target_minutes: 20
requires: [tf-17]
---
# tf-18 Lint and scan in CI

`terraform validate` only proves the code parses. The CTO wants two more gates on every pull
request: `tflint`, for mistakes Terraform accepts (unused variables, missing version pins,
invalid Azure values), and `trivy`, for insecure configuration. A finding fails the pull
request, and the team fixes it or writes down why it's acceptable.

## Deliverables

- [ ] `.tflint.hcl` at the root of the repo with the `terraform` plugin (`preset =
      "recommended"`) and the azurerm ruleset: `plugin "azurerm"`, `version = "0.29.0"`,
      `source = "github.com/terraform-linters/tflint-ruleset-azurerm"`.
- [ ] Two steps in the `plan` job, before `azure/login`, still exactly the jobs `plan` and
      `apply`:
  - `tflint --init`, then tflint over every stack and module under `terraform/`
    (`--recursive`) with that config. Any warning fails the step.
  - `trivy config` over `terraform/` that fails the job on `HIGH` and `CRITICAL` findings
    (`--exit-code 1`; trivy exits 0 otherwise).
- [ ] Run both locally first and deal with every finding: fix it, or, if it's a deliberate
      platform decision, accept it in a `.trivyignore.yaml` entry (or an inline
      `trivy:ignore` comment) with a `statement` that says why. No blanket skips: no
      `--skip-dirs`, no `--exit-code 0`, no dropped severities.
- [ ] Ship it as a PR. The plan job is green with both steps, the env stacks plan
      `No changes.` Merge it; the run on `main` is green.

## Done when

`./lab.sh grade` passes: `.tflint.hcl` enables the azurerm ruleset, the plan job runs tflint and
a failing trivy config scan before logging in to Azure, and the latest pull request run and the latest run on `main` are
green.
