# tf-27 hints

Docs:
- `terraform plan -detailed-exitcode`: https://developer.hashicorp.com/terraform/cli/commands/plan#other-options
- Scheduled workflows: https://docs.github.com/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule
- `gh issue create` / `gh label create`: https://cli.github.com/manual/gh_issue_create
- NSG rules as attributes: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group

Traps:
- **Exit codes, not output.** `-detailed-exitcode` returns 0 (no changes), 1 (error) and 2
  (changes). GitHub runs `run:` steps with `bash -e`, so a plain `terraform plan` that exits 2
  ends the step. Catch the code: `terraform plan ... -detailed-exitcode || rc=$?`.
- **`terraform_wrapper: false`** in `hashicorp/setup-terraform`, or the wrapper swallows the
  exit code.
- **Error is not drift.** Exit code 1 (a lock, an expired login, a broken stack) must fail the
  run, but it's no reason to open a drift issue.
- **The label must exist** before `gh issue create --label drift`:
  `gh label create drift --force` creates or updates it. The token needs `issues: write`.
- **Who are you on a schedule?** A scheduled or dispatched run is on `main`, so its OIDC subject
  ends in `:ref:refs/heads/main`: the `gh-main` credential from tf-04 already trusts it.
- **Put the drift back or keep it?** A tag someone changed by hand: apply the code (re-run the
  pipeline for that stack: `gh workflow run terraform.yml -f stacks=env-dev`). If the change was
  right, write it into the code instead; either way the next plan is clean.
- **Not everything shows up in a plan.** Terraform compares what it manages. The spoke module
  declares the NSGs without inline `security_rule` blocks, and for this resource the provider
  treats the rule list as optional and computed: rules someone adds outside Terraform are read
  into the state and never planned away. If the plan doesn't mention what the teammate saw,
  look in Azure: `az network nsg rule list -g rg-{{PREFIX}}-dev --nsg-name nsg-{{PREFIX}}-dev-app -o table`.
  Remove what nobody owns, and write down who decides about it next time.
- **The policy from tf-11 saw it too.** Nobody could *remove* the owner tag: the deny policy
  blocks any update that leaves an `rg-*` group without one. Changing its value was allowed.
- **Going further: bootstrap is blind to drift.yml.** `stacks.sh` skips `terraform/bootstrap`
  on purpose (CI never manages its own identity and RBAC), so nobody notices if someone widens
  CI's role assignments or its federated credentials by hand. A platform team covers it with a
  separate read-only check: a scheduled job under a different, reader-only identity that runs
  `terraform plan` on bootstrap, or an Azure Policy / activity-log alert on role assignment
  writes at subscription scope. In the lab you run `terraform plan` in `terraform/bootstrap`
  yourself now and then.
- **While the lab is paused** every env stack plans as "create everything". `./lab.sh pause`
  disables `drift.yml` and `./lab.sh resume` enables it again, so you don't wake up to drift
  issues about stacks you destroyed on purpose.
