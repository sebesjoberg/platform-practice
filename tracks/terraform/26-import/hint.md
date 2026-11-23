# tf-26 hints

Docs:
- `import` blocks: https://developer.hashicorp.com/terraform/language/import
- Generating configuration for imported resources: https://developer.hashicorp.com/terraform/language/import/generating-configuration
- `azurerm_storage_account` (defaults and the import ID): https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account
- Trivy ignore files: https://trivy.dev/latest/docs/configuration/filtering/

Traps:
- **Let Terraform write the first draft.** Add only the `import` blocks, then plan locally with
  `terraform plan -generate-config-out=generated.tf` (in `terraform/landing-zone`, with
  `TF_VAR_budget_email` exported). The generated file lists every argument as Azure reports
  it. Trim it to what differs from the provider's defaults, use `var.prefix`/`var.suffix` and
  your tag locals, and delete `generated.tf` before you commit. Never commit generated code
  you haven't read.
- **Import IDs are Azure resource IDs:** `az group show -n rg-{{PREFIX}}-legacy --query id -o tsv`
  and `az storage account show -n st{{PREFIX}}legacy{{SUFFIX}} --query id -o tsv`.
- **landing-zone has no `suffix` yet.** Add the variable the way the env stacks have it
  (validated, `{{SUFFIX}}` as the default).
- **Read the import plan line by line.** `allow_nested_items_to_be_public` defaults to `true` in
  azurerm 4.x, while the account was created without public blob access; a change there would
  open it up. Write `account_replication_type` as it was created (`LRS`), and the tags. A
  `forces replacement` anywhere means stop: that's the recreate you must avoid.
- **Why two PRs.** An `import` block fails when its object doesn't exist. Leave it in and every
  rebuild from scratch (a `./lab.sh nuke` and a fresh start, the capstone) breaks. Import blocks
  are one-shot tools.
- **Why the plan says "change".** The policy from tf-11 forced the teammate to tag the group, but
  with `managed_by = "clickops"`. Adopting the account means it follows your conventions now, so
  PR 1 updates the tags in place. Tags never force a replacement.
- **The pipeline imports, not you.** You can run `terraform import` locally, but then the change
  never went through review. With `import` blocks the import is part of the PR's plan, reviewed
  and applied like any other change.
