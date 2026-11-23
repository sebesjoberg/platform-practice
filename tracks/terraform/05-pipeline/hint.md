# tf-05 hints

Docs:
- `azure/login` with OpenID Connect: https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect
- azurerm provider with OIDC in GitHub Actions: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_oidc
- Workflow syntax (`workflow_dispatch` inputs, `permissions`, `concurrency`): https://docs.github.com/actions/reference/workflows-and-actions/workflow-syntax
- Variables: https://docs.github.com/actions/how-tos/write-workflows/choose-what-workflows-do/use-variables

Traps:
- **`id-token: write` is per job and replaces the defaults.** Once you set `permissions` on a
  job, everything you don't list is `none`. The plan job also needs `pull-requests: write` to
  comment, and `actions/checkout` needs `contents: read`.
- **The status check name is the job name.** tf-06 makes the check `plan` required. A matrix
  job reports as `plan (landing-zone)`, which never satisfies a required `plan` check. Loop
  over the stacks inside one job instead.
- **`AADSTS700213: No matching federated identity record`** means the token's subject doesn't
  match a credential from tf-04. Pull requests present `...:pull_request` and pushes to main
  `...:ref:refs/heads/main`. A job that sets `environment:` presents `...:environment:<name>`
  instead. `azure/login` fails early with a readable error, which is one reason to keep it even
  though Terraform could use OIDC on its own.
- **The backend needs `ARM_TENANT_ID` in CI** (locally it comes from `az login`). With
  `ARM_USE_AZUREAD=true` the backend uses Entra ID, through the container role from tf-04.
- **Variables vs. secrets:** `${{ vars.AZURE_CLIENT_ID }}`, not `${{ secrets... }}`. IDs aren't
  secrets. Keeping them visible makes debugging easier.
- **Script injection:** never put `${{ inputs.stacks }}` or other user input straight into a
  `run:` script. Pass it through `env:` and quote it.
- **`terraform_wrapper: false`** on `hashicorp/setup-terraform` keeps the output clean and the
  exit codes real.
- **Order matters once stacks depend on each other** (from tf-14). "Every directory" plus a
  known dependency order (landing-zone first) avoids a later rewrite.
- **New role assignments take a few minutes.** If the first run fails on the state blob with
  403, re-run it.
- Fork PRs on a public repo get no OIDC token, so their plan fails. That's expected and
  safe.
