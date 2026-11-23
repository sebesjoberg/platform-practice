# tf-17 hints

Docs:
- `terraform test`, run blocks, assertions and `expect_failures`: https://developer.hashicorp.com/terraform/language/tests
- Mock providers: https://developer.hashicorp.com/terraform/language/tests/mocking
- The `terraform test` command: https://developer.hashicorp.com/terraform/cli/commands/test

Traps:
- **A run without `command` applies.** The default is `command = apply`. With a mock provider
  that's harmless, but this lab keeps the tests plan-only: write `command = plan` in every run.
- **Unknown at plan time.** Under `command = plan` everything the provider computes (IDs, GUIDs)
  is unknown, so assert on what the module decides: names, prefixes, tags, counts,
  delegations. `azurerm_subnet.this["aca"].delegation[0].service_delegation[0].name` works;
  `azurerm_subnet.this["aca"].id` doesn't.
- **Lists vs. tuples.** `address_prefixes == ["10.1.4.0/23"]` is always false: the right side
  is a tuple, the left a `list(string)`. Compare elements (`address_prefixes[0] == "10.1.4.0/23"`)
  or wrap the literal in `tolist()`.
- **`expect_failures = [var.address_space]`** makes the run pass *because* the validation fails.
  A run whose validation unexpectedly passes fails the test.
- **The module has no defaults**, so the test file needs a top-level `variables { }` block with
  every required input. `hub.vnet_id` must look like a VNet ID if you validated it in tf-16. A
  run's own `variables { }` overrides single values.
- **`init` first.** `terraform test` needs the provider downloaded (`terraform init
  -backend=false` in the module directory). With only `>= 4.81` and no `< 5.0`, init picks
  azurerm 5.x and the module stops validating; see tf-16.
- **Where the step goes.** A step in the `plan` job, after `terraform fmt` and *before*
  `azure/login`: move the login step down to just above the plan step. Tests need no Azure, and
  nothing but Terraform itself should run with a logged-in session. Not a new job: `plan` is the
  required check (tf-06), and an extra job could fail while `plan` is skipped. A failed test
  stops the job before the plan step, so that PR gets no plan comment until the test passes.
- **Find the tests, don't hard-code them:** loop over the directories that contain a
  `tests/*.tftest.hcl`, and let the step pass when there is no `terraform/modules` at all (it
  goes away in tf-19).
