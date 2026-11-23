# tf-20 hints

Docs:
- Semantic versioning: https://semver.org/
- Keep a Changelog: https://keepachangelog.com/en/1.1.0/
- Module sources with `?ref=`: https://developer.hashicorp.com/terraform/language/modules/sources#selecting-a-revision
- Refactoring modules, including when a change is breaking: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring

Traps:
- **Why major.** Every caller that passes `address_space` gets "Unsupported argument" on 2.0.0.
  A new major version tells them before they upgrade; the changelog tells them what to do.
- **The rename touches four places in the module:** the variable block, every
  `var.address_space` (the `cidrsubnet()` call and the VNet's `address_space` attribute, which
  keeps its Azure name), the tests (`variables` blocks and `expect_failures = [var.vnet_cidr]`)
  and the README (re-run terraform-docs). `terraform test` finds what you missed.
- **No state change, no `moved`.** Variables aren't in the state. Resource addresses and
  attribute values stay the same, so both stacks plan `No changes.`: dev because its value is the
  same under the new name, prod because it didn't change at all.
- **Two versions of one module, side by side, is normal.** Each stack pins its own `?ref=`;
  `terraform init` fetches each separately. That's the canary: prod moves to v2 in a later
  pull request, once dev has run on it.
- **Don't move `v1.0.0`**, and don't release 2.0.0 as `v1.1.0`: a minor version promises callers
  that nothing breaks.
- **Tag after CI is green on `main`**, and push the tag before the platform PR: the plan job
  clones `?ref=v2.0.0`.
- **Locally**, `terraform init` in env-dev after changing `?ref=` (Terraform reports "Module
  source has changed").
