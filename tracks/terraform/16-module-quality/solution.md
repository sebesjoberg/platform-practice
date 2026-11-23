# tf-16 solution

## Approach

Everything happens inside `terraform/modules/spoke`; the stacks stay as they are. Describe and
validate the inputs, add outputs, relax the constraints to lower bounds, then generate the
README with terraform-docs. The PR plans `No changes.` in every stack.

## Code

`variables.tf` (two of the seven; the others follow the same pattern):

```hcl
variable "env" {
  description = "Environment of the spoke: dev or prod. Part of every resource name and the env tag."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "address_space" {
  description = "Address space of the spoke VNet, one /16 CIDR block. The subnets are cut out of it: snet-app x.1.0/24, snet-pe x.2.0/24, snet-aca x.4.0/23."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a /16 CIDR block, such as 10.1.0.0/16."
  }
}

variable "hub" {
  description = "The hub VNet the spoke peers with: its resource group (which also holds the private DNS zones), name and ID."
  type = object({
    resource_group_name = string
    vnet_name           = string
    vnet_id             = string
  })

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.hub.vnet_id))
    error_message = "hub.vnet_id must be the Azure resource ID of a virtual network."
  }
}
```

The reference also validates `prefix` (`^[a-z]{2,6}$`), `owner` (not empty) and
`private_dns_zone_names` (only `privatelink.*`); `location` only gets a description.

`outputs.tf`:

```hcl
output "resource_group_name" {
  description = "Name of the spoke's resource group (rg-<prefix>-<env>)."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the spoke VNet (vnet-<prefix>-<env>)."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs by short name: app, pe and aca."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}
```

`versions.tf`: the lower bounds the module needs, and a cap below azurerm 5.0, whose breaking
changes it was never written for. The stacks keep `~> 4.81`; that pin decides what runs.

```hcl
terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81, < 5.0"
    }
  }
}
```

`README.md`: a title, two sentences on what the module builds, a usage block (the env stacks'
module call), then the markers:

```markdown
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

## Commands

```bash
git switch -c spoke-module-quality
cd terraform/modules/spoke
# ...edit variables.tf, outputs.tf, versions.tf, write README.md with the markers
terraform-docs markdown table --output-file README.md --output-mode inject .
cd -
terraform fmt -recursive terraform
terraform -chdir=terraform/env-dev init -backend=false && terraform -chdir=terraform/env-dev validate
git add -A && git commit -m "spoke module: descriptions, validation, outputs, README"
git push -u origin spoke-module-quality
gh pr create --fill && gh pr checks --watch      # env-dev / env-prod: No changes.
gh pr merge --squash --delete-branch
```

## Verify

```bash
sed -n '/BEGIN_TF_DOCS/,/END_TF_DOCS/p' terraform/modules/spoke/README.md   # Inputs and Outputs tables
./lab.sh grade
```

## Cost

None: nothing in Azure changes.
