# {{MODULES_REPO}}

Terraform modules of the Acme platform, consumed by `{{LIVE_REPO}}` and, later, by other teams.

| Module | What it builds |
|---|---|
| [`spoke`](spoke/) | One environment's spoke network, peered with the hub |
| [`app-env`](app-env/) | One environment's app identity and Key Vault with a private endpoint (since v2.1.0) |
| [`linux-vm`](linux-vm/) | One Ubuntu 24.04 VM, SSH key only, optional public IP and identity (since v2.2.0) |

## Using a module

Always pin a release tag:

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v3.0.0"
  # ...
}
```

The `//spoke` part selects the module's directory in this repo; `?ref=` selects the version.
A release tags the whole repo: `v2.1.0` holds `spoke` exactly as `v2.0.0` did, plus `app-env`.
From `v3.0.0` the modules need azurerm 5.x; `v2.x` is the line for azurerm 4.x.
A stack may pin different releases for different modules.
Never point at `main`: a stack must not change because someone merged here.

## Releases

Versions follow semantic versioning and apply to the whole repo:

- patch (`v1.0.1`): fixes, no interface change
- minor (`v1.1.0`): new optional inputs or new outputs
- major (`v2.0.0`): anything a caller has to change (renamed or removed inputs, changed
  behaviour), with a migration note in [CHANGELOG.md](CHANGELOG.md)

A release is an annotated tag on `main` after CI is green:
`git tag -a v1.1.0 -m "..." && git push origin v1.1.0`. Tags are never moved or deleted once
pushed: stacks pin them.

## Development

CI (`.github/workflows/ci.yml`) runs `terraform fmt`, `validate`, `terraform test` (mock
providers, no Azure), tflint and trivy on every pull request and on `main`. Locally:

```bash
cd spoke && terraform init -backend=false && terraform test
```
