# tf-18 solution

## Approach

1. Install tflint and trivy locally (tf-01 mentioned them), write `.tflint.hcl`, and run both
   over `terraform/` until they're clean.
2. tflint passes on the reference code. trivy reports one CRITICAL finding, `AZU-0012`, on the
   state storage account. Accept it with a written reason in `.trivyignore.yaml`.
3. Add the two steps to the `plan` job, after the module tests and before the plan.

## Code

`.tflint.hcl`:

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
```

`.trivyignore.yaml`:

```yaml
misconfigurations:
  - id: AZU-0012
    paths:
      - "bootstrap/state.tf"
    statement: >-
      The state account keeps its public endpoint with default action Allow: GitHub-hosted
      runners and our WSL machines have no fixed IPs, and there is no runner inside the VNet
      before tf-25. Access is Entra ID only (shared keys disabled, no anonymous blob access,
      TLS 1.2). Revisit when CI runs on the self-hosted runner.
```

`.github/workflows/terraform.yml`, in the `plan` job after `terraform test (modules)`:

```yaml
      - uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: v0.66.0
      - name: tflint
        env:
          GITHUB_TOKEN: ${{ github.token }} # tflint --init downloads the azurerm ruleset from GitHub
        run: |
          tflint --init --config "$GITHUB_WORKSPACE/.tflint.hcl"
          tflint --recursive --config "$GITHUB_WORKSPACE/.tflint.hcl" --chdir terraform
      - name: trivy config scan
        env:
          TRIVY_VERSION: "0.76.2"
        run: |
          curl -sSfL "https://raw.githubusercontent.com/aquasecurity/trivy/v${TRIVY_VERSION}/contrib/install.sh" |
            sh -s -- -b "$RUNNER_TEMP/bin" "v${TRIVY_VERSION}"
          "$RUNNER_TEMP/bin/trivy" config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml terraform
```

## Commands

```bash
git switch -c lint-scan
tflint --init --config "$PWD/.tflint.hcl"
tflint --recursive --config "$PWD/.tflint.hcl" --chdir terraform; echo "tflint exit $?"
trivy config --exit-code 1 --severity HIGH,CRITICAL terraform; echo "trivy exit $?"
#   bootstrap/state.tf: AZU-0012 (CRITICAL) -> write .trivyignore.yaml, then:
trivy config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml terraform; echo "trivy exit $?"
git add -A && git commit -m "CI: tflint and trivy in the plan job"
git push -u origin lint-scan
gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch
```

To see the gate work, add an unused `variable "x" { type = string }` to a stack on a branch:
tflint fails the plan job.

## Verify

```bash
gh run list --workflow terraform.yml --limit 3        # newest PR run and main run: success
./lab.sh grade
```

## Cost

None in Azure; a few extra seconds per pull request.
