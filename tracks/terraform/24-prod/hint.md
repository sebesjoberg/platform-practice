# tf-24 hints

Docs:
- Deployment environments and required reviewers: https://docs.github.com/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment
- Job outputs: https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/passing-information-between-jobs
- OIDC subject claims for environments: https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims
- Reviewing deployments: https://docs.github.com/actions/managing-workflow-runs-and-deployments/managing-deployments/reviewing-deployments

Traps:
- **Why a separate job, not a step?** The approval gate is per job: `environment: prod` makes
  GitHub hold the whole job until a reviewer approves. It also changes the job's OIDC subject
  from `…:ref:refs/heads/main` to `…:environment:prod`. Only `gh-env-prod` trusts that subject,
  so a prod apply can't happen outside that environment, and an apply inside it can't happen
  without approval.
- **Keep `plan` independent.** `plan` is the required check. If it needed another job and that
  job failed, `plan` would be skipped, and a skipped required check counts as passed. Extra
  jobs that depend on `apply` are fine: they never run on pull requests.
- **Skip env-prod in `apply`, don't drop it from discovery.** `stacks.sh` still lists it (the
  plan job needs it). Filter it out of `apply`'s list, and pass a job output such as
  `prod=true` so `apply-prod` runs only when it was selected
  (`gh workflow run terraform.yml -f stacks=env-dev` must not wait for an approval). A
  dispatch of only `env-prod` leaves `apply` with nothing to do; that's fine.
- **Concurrency.** If `apply-prod` shared `apply`'s concurrency group, a run waiting for your
  approval would block every later dev apply.
- **`needs: apply` and failures.** When `apply` fails, `apply-prod` is skipped: prod never gets
  a change that broke dev or shared.
- **Two releases in one stack.** env-prod pins spoke at `v2.0.0` and app-env at `v2.1.0`,
  exactly as env-dev does. Moving spoke to `v2.0.0` renames the input (`vnet_cidr`) and plans
  `No changes.` for the spoke resources; the plan adds only the app-env resources and
  `AcrPull`.
- **Approvals and pause.** `./lab.sh pause` destroys env-prod; the next resume's run waits for
  your approval before it rebuilds it.
