---
id: tf-06
title: Protect main
target_minutes: 15
requires: [tf-05]
---
# tf-06 Protect main

The pipeline only helps if nobody goes around it. The CTO wants `main` changed through pull
requests with a green plan and nothing else. Production deployments will also need a human
"yes". You're the only engineer, so that human is you.

## Deliverables

On `{{GH_OWNER}}/{{LIVE_REPO}}`:

- [ ] An **active** repository ruleset (name it `protect-main`) that targets `main` and:
  - requires a pull request before merging, with **0** required approvals (you can't
    approve your own PRs)
  - requires the status check `plan` to pass
  - blocks force pushes
  - blocks branch deletion
  - lets the **Repository admin** role bypass it, mode *always*. `./lab.sh catchup`
    force-pushes `main` and would otherwise be locked out.
- [ ] An environment `prod` with **you** (`{{GH_OWNER}}`) as a required reviewer.
- [ ] Proof it works: open a small PR (a README tweak is enough) and watch the merge box
      wait for the `plan` check before it lets you merge.

## Done when

`gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/rules/branches/main` lists `pull_request`,
`required_status_checks`, `non_fast_forward` and `deletion`, the repo settings show `prod`
with you as reviewer, and `./lab.sh grade` passes.

Target: 15 minutes.
