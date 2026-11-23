# tf-17 solution

## Approach

1. One test file next to the module, `tests/spoke.tftest.hcl`: a mock provider, shared
   `variables`, then plan-only runs: the dev layout, a prod variation, and two runs that expect
   a validation failure.
2. One workflow step in the `plan` job that finds every module with tests and runs
   `terraform init -backend=false` + `terraform test` in it.

## Code

`terraform/modules/spoke/tests/spoke.tftest.hcl` (shortened; the reference asserts on the NSGs,
peerings and DNS links too):

```hcl
mock_provider "azurerm" {}

variables {
  env           = "dev"
  address_space = "10.1.0.0/16"
  prefix        = "acme"
  location      = "swedencentral"
  owner         = "platform-team"

  hub = {
    resource_group_name = "rg-acme-hub"
    vnet_name           = "vnet-acme-hub"
    vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/virtualNetworks/vnet-acme-hub"
  }

  private_dns_zone_names = ["privatelink.vaultcore.azure.net", "privatelink.blob.core.windows.net"]
}

run "dev_names_and_layout" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-acme-dev" && azurerm_virtual_network.this.name == "vnet-acme-dev"
    error_message = "the spoke must be rg-<prefix>-<env> / vnet-<prefix>-<env>"
  }

  assert {
    condition     = azurerm_subnet.this["app"].address_prefixes[0] == "10.1.1.0/24" && azurerm_subnet.this["pe"].address_prefixes[0] == "10.1.2.0/24" && azurerm_subnet.this["aca"].address_prefixes[0] == "10.1.4.0/23"
    error_message = "subnets must be app x.1.0/24, pe x.2.0/24 and aca x.4.0/23"
  }

  assert {
    condition     = azurerm_subnet.this["aca"].delegation[0].service_delegation[0].name == "Microsoft.App/environments" && length(azurerm_subnet.this["app"].delegation) == 0
    error_message = "only snet-aca is delegated, to Microsoft.App/environments"
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == 2
    error_message = "one link per private DNS zone"
  }
}

run "prod_layout" {
  command = plan

  variables {
    env           = "prod"
    address_space = "10.2.0.0/16"
  }

  assert {
    condition     = azurerm_subnet.this["aca"].address_prefixes[0] == "10.2.4.0/23"
    error_message = "prod cuts its subnets out of 10.2.0.0/16"
  }
}

run "rejects_an_address_space_that_is_not_a_16" {
  command = plan

  variables {
    address_space = "10.1.0.0/24"
  }

  expect_failures = [var.address_space]
}

run "rejects_an_unknown_env" {
  command = plan

  variables {
    env = "test"
  }

  expect_failures = [var.env]
}
```

`.github/workflows/terraform.yml`, a new step in the `plan` job right after `terraform fmt`:

```yaml
      - name: terraform test (modules)
        run: |
          if [ ! -d terraform/modules ]; then echo "no modules under terraform/modules"; exit 0; fi
          for d in $(find terraform/modules -name '*.tftest.hcl' -path '*/tests/*' -exec dirname {} \; | xargs -r -n1 dirname | sort -u); do
            echo "::group::terraform test $d"
            terraform -chdir="$d" init -backend=false -input=false
            terraform -chdir="$d" test
            echo "::endgroup::"
          done
```

## Commands

```bash
git switch -c spoke-tests
cd terraform/modules/spoke
terraform init -backend=false
terraform test            # 4 passed, 0 failed
cd -
git add -A && git commit -m "spoke module: plan-only tests with a mock provider, run in CI"
git push -u origin spoke-tests
gh pr create --fill && gh pr checks --watch
gh pr merge --squash --delete-branch
```

To see a test catch something, change `netnum = 2` to `netnum = 3` for `aca` and run
`terraform test` again (then change it back).

## Verify

```bash
id="$(gh run list --workflow terraform.yml --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$id"                                   # completed, success
gh run view "$id" --log | grep -A6 "terraform test" # the test output in CI
./lab.sh grade
```

## Cost

None: mock providers never call Azure.
