# tf-07 hints

Docs:
- Input variables and custom validation: https://developer.hashicorp.com/terraform/language/values/variables
- Local values: https://developer.hashicorp.com/terraform/language/values/locals
- `for` expressions, `merge`, `concat`, `sort`: https://developer.hashicorp.com/terraform/language/expressions/for
- Azure naming and tagging guidance (Cloud Adoption Framework): https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming

Traps:
- **A refactor must plan "No changes".** If the plan wants to update `rg-{{PREFIX}}-hub`, a
  tag value or the name differs from before. A changed name forces a *replacement* of the
  group. Read the plan before you merge, every time.
- **Validation can only look at its own variable** (Terraform 1.9+ also allows other
  variables, but keep it simple). `contains(["dev", "prod"], e)` inside `alltrue([...])`
  checks every element of a set.
- **A set has no order.** `for` over a set works, but `concat` needs a list: use
  `sort(var.envs)` or `tolist(var.envs)`.
- **Unused variables are lint errors.** tflint's recommended rules flag a variable nobody reads
  (CI adds tflint in tf-18). Building the tag maps from `var.envs` uses it already.
- **No tfvars file in CI.** `*.tfvars` is gitignored and the repo is public, so defaults carry
  the values. A variable without a default makes `plan -input=false` fail.
- `terraform plan -var location=westeurope` runs locally without changing anything; you need
  `az login` and the backend (`terraform init`).
