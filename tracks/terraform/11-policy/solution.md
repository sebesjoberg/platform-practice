# tf-11 solution

## Approach

1. Least privilege for CI: one extra role, *Resource Policy Contributor*, which covers policy
   definitions, assignments and exemptions and nothing else in `Microsoft.Authorization`.
   It goes into `bootstrap` because CI never manages its own permissions, and you apply it
   locally before the pipeline needs it.
2. A custom definition for the owner tag (mode `All`, so resource groups are evaluated),
   assigned at the subscription.
3. The built-in *Allowed locations*, assigned with `["swedencentral"]`. Its rule already skips
   `global` resources:

   ```json
   "if": { "allOf": [
     { "field": "location", "notIn": "[parameters('listOfAllowedLocations')]" },
     { "field": "location", "notEquals": "global" },
     { "field": "type", "notEquals": "Microsoft.AzureActiveDirectory/b2cDirectories" }
   ] }
   ```

   So private DNS zones, their links and action groups (all `global`) keep working without
   `global` in the list.

## Code

`terraform/bootstrap/ci-policy.tf`:

```hcl
resource "azurerm_role_assignment" "ci_policy" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Resource Policy Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
  principal_type       = "ServicePrincipal"
}
```

`terraform/landing-zone/policy.tf`:

```hcl
data "azurerm_subscription" "current" {}

data "azurerm_policy_definition" "allowed_locations" {
  name = "e56962a6-4747-49cd-b67b-bf8b01975c4c" # built-in "Allowed locations"
}

resource "azurerm_policy_definition" "require_owner_tag" {
  name         = "${var.prefix}-require-owner-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require an owner tag on rg-* resource groups"

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { field = "name", like = "rg-*" },
        { field = "tags['owner']", exists = "false" },
      ]
    }
    then = { effect = "deny" }
  })
}

resource "azurerm_subscription_policy_assignment" "require_owner_tag" {
  name                 = "${var.prefix}-require-owner-tag"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.require_owner_tag.id
}

resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "${var.prefix}-allowed-locations"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id
  parameters = jsonencode({
    listOfAllowedLocations = { value = [var.location] }
  })
}
```

Why `rg-*` only: Azure creates some groups itself, without your tags. `NetworkWatcherRG` appears
when the first VNet in a region is created, and a Container Apps environment (tf-23) creates an
infrastructure group. A deny on *every* untagged group would break those deployments. Scoping
the rule to the naming convention keeps the guardrail where it matters.

## Commands

```bash
# 1. CI permission, locally (you are Owner)
cd terraform/bootstrap && terraform init && terraform apply && cd ../..

# 2. the policy, through the pipeline
git switch -c policy
git add terraform/bootstrap terraform/landing-zone
git commit -m "Policy: require owner tag on rg-*, allowed locations swedencentral"
git push -u origin policy
gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
az policy assignment list --query "[?starts_with(name, '{{PREFIX}}-')].{name:name, def:policyDefinitionId}" -o table
az group create -n rg-{{PREFIX}}-policytest -l {{LOCATION}}     # RequestDisallowedByPolicy
az group create -n rg-{{PREFIX}}-policytest -l westeurope --tags owner={{OWNER_TAG}}   # allowed: groups aren't Indexed
az group delete -n rg-{{PREFIX}}-policytest --yes 2>/dev/null   # if one got through
./lab.sh grade
```

The second create shows the limit of the built-in: a resource group's location is only
metadata, so *Allowed locations* doesn't evaluate groups. Delete it right away.

## Cost

Azure Policy is free.
