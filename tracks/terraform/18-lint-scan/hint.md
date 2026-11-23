# tf-18 hints

Docs:
- tflint configuration, plugins and `--recursive`: https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md
- The azurerm ruleset: https://github.com/terraform-linters/tflint-ruleset-azurerm
- trivy misconfiguration scanning and ignoring findings: https://trivy.dev/latest/docs/scanner/misconfiguration/ and https://trivy.dev/latest/docs/configuration/filtering/
- setup-tflint action: https://github.com/terraform-linters/setup-tflint

Traps:
- **What trivy finds here:** `AZU-0012` (CRITICAL) on the state storage account in
  `bootstrap`: no network rules, default action Allow. Locking it down (`default_action =
  "Deny"` with an IP allow-list) would lock out the GitHub-hosted runners and your laptop, which
  have no fixed IPs; the account is protected by Entra ID only, shared keys off, TLS 1.2. That
  is a decision, so record it: a `.trivyignore.yaml` entry with `id`, `paths` (relative to the
  scanned directory, e.g. `bootstrap/state.tf`) and a `statement`, passed with `--ignorefile`.
  Don't skip `bootstrap` to make the finding go away. It's the most sensitive stack you have.
- **trivy's exit code is 0 by default**, findings or not. Without `--exit-code 1` the step is
  decoration.
- **tflint warnings fail too**: tflint exits non-zero on any issue of severity warning or
  higher, and the recommended preset is all warnings (unused declarations, missing
  `required_version`/`required_providers`, unpinned module sources).
- **`tflint --init` downloads the azurerm ruleset from GitHub.** In CI give it
  `GITHUB_TOKEN: ${{ github.token }}` or it may hit the anonymous API rate limit.
- **`--config` needs an absolute path with `--recursive`/`--chdir`.** Relative paths resolve
  per directory: use `"$GITHUB_WORKSPACE/.tflint.hcl"` in CI, `"$PWD/.tflint.hcl"` locally.
- **Pin versions** of tflint (`tflint_version`), the ruleset (`version` in `.tflint.hcl`) and
  trivy. A new rule in a newer version should arrive in a PR, not break `main` overnight.
- **Same job, not new jobs.** Lint and scan belong in `plan`, the required check (tf-06). Put
  them after the module tests and before `azure/login`: a failing gate costs seconds, not a full
  plan, and third-party tools (a downloaded ruleset, an install script) never run with a
  logged-in Azure session.
