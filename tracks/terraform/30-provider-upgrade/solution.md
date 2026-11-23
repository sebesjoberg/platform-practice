# tf-30 solution

## What 5.0 breaks here

| Change in 5.0 | Where | Fix |
|---|---|---|
| No resource providers registered by default | every stack | `resource_providers_to_register = [...]` in each provider block |
| `azurerm_private_dns_zone_virtual_network_link`: `resource_group_name` and `private_dns_zone_name` removed | landing-zone `dns.tf`, spoke `hub.tf` | `private_dns_zone_id`; spoke input `private_dns_zone_ids` |
| Modules capped `< 5.0` | all three modules | `>= 5.14, < 6.0`, release `v3.0.0` |

## Modules repo

`versions.tf` of each module: `version = ">= 5.14, < 6.0"`.

`spoke/hub.tf`:

```hcl
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zone_ids

  name                 = "link-${azurerm_virtual_network.this.name}"
  private_dns_zone_id  = each.value
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = local.tags
}
```

`spoke/variables.tf`, replacing `private_dns_zone_names`:

```hcl
variable "private_dns_zone_ids" {
  description = "Private DNS zones to link the spoke VNet to: zone name (privatelink.*) => the zone's resource ID."
  type        = map(string)

  validation {
    condition     = alltrue([for name, id in var.private_dns_zone_ids : startswith(name, "privatelink.") && endswith(lower(id), "/providers/microsoft.network/privatednszones/${name}")])
    error_message = "private_dns_zone_ids must map privatelink.* zone names to the resource IDs of those zones."
  }
}
```

In `spoke/tests/spoke.tftest.hcl`, the `variables` block passes `private_dns_zone_ids` with two
fake zone IDs instead of `private_dns_zone_names`. Then:

```bash
cd "$MODULES_DIR"
for m in spoke app-env linux-vm; do (cd $m && terraform init -upgrade -backend=false && terraform test \
  && terraform-docs markdown table --output-file README.md --output-mode inject .); done
# CHANGELOG.md: "## 3.0.0" with Breaking (azurerm 5.x; private_dns_zone_names -> private_dns_zone_ids) and Migration
git switch -c azurerm-5 && git add -A && git commit -m "azurerm 5.x (v3.0.0)" && git push -u origin azurerm-5
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull && git tag -a v3.0.0 -m "v3.0.0: azurerm 5.x" && git push origin v3.0.0
```

## Platform repo

Each stack's `versions.tf` (the starters):

```hcl
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
...
provider "azurerm" {
  subscription_id = "{{SUBSCRIPTION_ID}}"

  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.Compute",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
  ] # env-dev's list; every stack names its own

  features { ... }
}
```

`terraform/landing-zone/dns.tf`, the hub links:

```hcl
  name                = "link-${azurerm_virtual_network.hub.name}"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = azurerm_virtual_network.hub.id
```

`terraform/env-dev/main.tf` and `env-prod/main.tf`: `?ref=v3.0.0` on both modules, and

```hcl
  private_dns_zone_ids = { for name, zone in data.azurerm_private_dns_zone.hub : name => zone.id }
```

`shared/jump.tf` and `env-dev/web.tf`: `linux-vm?ref=v3.0.0`.

Lock files, from the repo root:

```bash
for s in bootstrap landing-zone observability shared env-dev env-prod; do
  (cd terraform/$s && terraform init -upgrade -backend=false -input=false >/dev/null &&
    terraform providers lock -platform=linux_amd64 -platform=windows_amd64)
done
```

`.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: terraform
    directories:
      - "/terraform/bootstrap"
      - "/terraform/landing-zone"
      - "/terraform/observability"
      - "/terraform/shared"
      - "/terraform/env-dev"
      - "/terraform/env-prod"
    schedule:
      interval: weekly
    groups:
      terraform-minor:
        patterns: ["*"]
        update-types: [minor, patch]
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: monthly
```

Dependabot secrets, then the PR:

```bash
gh secret set --app dependabot BUDGET_EMAIL -R {{GH_OWNER}}/{{LIVE_REPO}} --body <your email>
gh secret set --app dependabot LEARNER_IP -R {{GH_OWNER}}/{{LIVE_REPO}} --body {{LEARNER_IP}}
git switch -c azurerm-5 && git add -A && git commit -m "tf-30: azurerm 5.x, lock files, Dependabot"
git push -u origin azurerm-5 && gh pr create --fill
# plan comment: "No changes." for every stack
gh pr checks --watch && gh pr merge --squash --delete-branch   # approve apply-prod in the Actions tab
cd terraform/bootstrap && terraform init -upgrade && terraform apply   # No changes.
```

## Verify

```bash
grep -c '"h1:' terraform/*/.terraform.lock.hcl     # 2 per provider: linux_amd64 and windows_amd64
gh api repos/{{GH_OWNER}}/{{LIVE_REPO}}/dependabot/secrets --jq '.secrets[].name'
gh api repos/{{GH_OWNER}}/{{MODULES_REPO}}/git/refs/tags/v3.0.0 --jq .ref
```
