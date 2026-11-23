# tf-07 solution

## Approach

Inputs become validated variables with the lab values as defaults. Tags and the naming pattern
live in one `locals` block that every resource reads. The resource group gets exactly the
same name, location and tags as before, so the plan is empty: the refactor is proven safe.

## Code

`terraform/landing-zone/variables.tf`:

```hcl
variable "prefix" {
  description = "Company prefix in every resource name (<type>-<prefix>-<name>)."
  type        = string
  default     = "{{PREFIX}}"

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase letters."
  }
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "{{LOCATION}}"

  validation {
    condition     = var.location == "swedencentral"
    error_message = "The platform runs in swedencentral only."
  }
}

variable "owner" {
  description = "Value of the owner tag on every resource group."
  type        = string
  default     = "{{OWNER_TAG}}"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "envs" {
  description = "Application environments. Each gets a spoke network (tf-09)."
  type        = set(string)
  default     = ["dev", "prod"]

  validation {
    condition     = length(var.envs) > 0 && alltrue([for e in var.envs : contains(["dev", "prod"], e)])
    error_message = "envs may only contain \"dev\" and \"prod\"."
  }
}
```

`terraform/landing-zone/main.tf`:

```hcl
locals {
  base_tags = {
    owner      = var.owner
    managed_by = "terraform"
  }

  # local.tags["hub"], local.tags["dev"], local.tags["prod"]
  tags = {
    for env in concat(["hub"], sort(var.envs)) : env => merge(local.base_tags, { env = env })
  }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.prefix}-hub"
  location = var.location
  tags     = local.tags["hub"]
}
```

Why defaults instead of a tfvars file: `*.tfvars` is gitignored (tf-01) and the repo is public.
These values aren't secret, and defaults keep CI simple. The one personal value (the budget
email in tf-12) comes from a GitHub variable instead.

## Commands

```bash
cd terraform/landing-zone
terraform fmt && terraform validate
terraform init && terraform plan                       # No changes.
terraform plan -var location=westeurope                # fails: The platform runs in swedencentral only.
terraform plan -var 'envs=["dev","test"]'              # fails: envs may only contain "dev" and "prod".
cd ../..
git switch -c conventions
git add terraform/landing-zone
git commit -m "landing-zone: naming and tagging conventions"
git push -u origin conventions
gh pr create --fill && gh pr checks --watch            # plan comment: landing-zone: No changes.
gh pr merge --squash --delete-branch
```

## Verify

```bash
az group show -n rg-{{PREFIX}}-hub --query tags        # unchanged: owner, env=hub, managed_by
./lab.sh grade
```

## Cost

Nothing changes in Azure.
