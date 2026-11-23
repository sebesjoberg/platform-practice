# tf-20 solution

## Approach

1. In the modules repo: rename the input, update tests and README, write the changelog, merge,
   tag `v2.0.0`.
2. In the platform repo: move env-dev to `v2.0.0` and rename the argument in its module call;
   leave env-prod alone. One PR, `No changes.` in both stacks.

## Code

`spoke/variables.tf`:

```hcl
variable "vnet_cidr" {
  description = "CIDR block of the spoke VNet, one /16; the subnets are cut out of it: snet-app x.1.0/24, snet-pe x.2.0/24, snet-aca x.4.0/23. Called address_space before v2.0.0."
  type        = string

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && endswith(var.vnet_cidr, "/16")
    error_message = "vnet_cidr must be a /16 CIDR block, such as 10.1.0.0/16."
  }
}
```

`spoke/main.tf`: `cidrsubnet(var.vnet_cidr, s.newbits, s.netnum)` in the locals and
`address_space = [var.vnet_cidr]` on the VNet (the Azure attribute keeps its name).

`spoke/tests/spoke.tftest.hcl`: `vnet_cidr = "10.1.0.0/16"` in the shared `variables`,
`vnet_cidr = "10.2.0.0/16"` in the prod run, and the failing run becomes:

```hcl
run "rejects_a_vnet_cidr_that_is_not_a_16" {
  command = plan

  variables {
    vnet_cidr = "10.1.0.0/24"
  }

  expect_failures = [var.vnet_cidr]
}
```

`CHANGELOG.md`:

```markdown
# Changelog

## 2.0.0 (2026-11-23)

### Breaking

- `spoke`: the input `address_space` is renamed to `vnet_cidr`. Same type (`string`), same
  validation (a /16).

### Migration from 1.x

1. Change the module source's `?ref=` to `v2.0.0`.
2. Rename the argument in the module call: `address_space = …` becomes `vnet_cidr = …`.
3. Plan. Expect `No changes.`

Roll it out one environment at a time: dev first, prod once dev has run on 2.0.0.

## 1.0.0 (2026-11-23)

- `spoke`: first release.
```

`terraform/env-dev/main.tf` in the platform repo:

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v2.0.0"

  env       = var.env
  vnet_cidr = var.address_space
  prefix    = var.prefix
  location  = var.location
  owner     = var.owner
  # hub and private_dns_zone_names as before
}
```

`terraform/env-prod/main.tf`: unchanged (`?ref=v1.0.0`, `address_space = var.address_space`).

## Commands

```bash
cd "$MODULES_DIR" && git switch main && git pull && git switch -c vnet-cidr
# ...rename in spoke/*.tf and spoke/tests/, write CHANGELOG.md
(cd spoke && terraform-docs markdown table --output-file README.md --output-mode inject . && terraform test)
git add -A && git commit -m "spoke: rename address_space to vnet_cidr (breaking, 2.0.0)"
git push -u origin vnet-cidr
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull
git tag -a v2.0.0 -m "spoke v2.0.0: address_space renamed to vnet_cidr" && git push origin v2.0.0

cd "$LIVE_DIR" && git switch main && git pull && git switch -c spoke-v2-dev
# ...edit terraform/env-dev/main.tf
terraform -chdir=terraform/env-dev init -backend=false && terraform -chdir=terraform/env-dev validate
git add -A && git commit -m "env-dev: spoke module v2.0.0 (prod stays on v1)"
git push -u origin spoke-v2-dev
gh pr create --fill && gh pr checks --watch      # env-dev and env-prod: No changes.
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
git -C "$MODULES_DIR" show v1.0.0:spoke/variables.tf | grep 'variable "address_space"'
git -C "$MODULES_DIR" show v2.0.0:spoke/variables.tf | grep 'variable "vnet_cidr"'
grep -rn '?ref=' terraform/env-*/       # env-dev v2.0.0, env-prod v1.0.0
./lab.sh grade
```

## Cost

None in Azure.
