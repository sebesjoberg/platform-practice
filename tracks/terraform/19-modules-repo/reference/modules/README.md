# {{MODULES_REPO}}

Terraform modules of the Acme platform, consumed by `{{LIVE_REPO}}` and, later, by other teams.

| Module | What it builds |
|---|---|
| [`spoke`](spoke/) | One environment's spoke network, peered with the hub |

## Using a module

Always pin a release tag:

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v1.0.0"
  # ...
}
```

The `//spoke` part selects the module's directory in this repo; `?ref=` selects the version.
Never point at `main`: a stack must not change because someone merged here.

## Releases

Versions follow semantic versioning and apply to the whole repo:

- patch (`v1.0.1`): fixes, no interface change
- minor (`v1.1.0`): new optional inputs or new outputs
- major (`v2.0.0`): anything a caller has to change (renamed or removed inputs, changed
  behaviour)

A release is an annotated tag on `main` after CI is green:
`git tag -a v1.1.0 -m "..." && git push origin v1.1.0`. Tags are never moved or deleted once
pushed: stacks pin them.

## Development

CI (`.github/workflows/ci.yml`) runs `terraform fmt`, `validate`, `terraform test` (mock
providers, no Azure), tflint and trivy on every pull request and on `main`. Locally:

```bash
cd spoke && terraform init -backend=false && terraform test
```
