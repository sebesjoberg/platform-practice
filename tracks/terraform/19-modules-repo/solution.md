# tf-19 solution

## Approach

1. Create the public modules repo and clone it to `MODULES_DIR`.
2. Copy the module with its tests and README into `spoke/`, add the repo files and the starter
   CI workflow, push to `main`, wait for CI, then tag `v1.0.0` and push the tag.
3. In the platform repo, point both env stacks at the tag and delete the local module, in one
   PR. The state addresses don't change (`module.spoke.*`), so the plan is `No changes.`

## Code

Modules repo layout:

```text
{{MODULES_REPO}}/
  .github/workflows/ci.yml     # from ~/.platform-lab/starter/tf-19/ci.yml
  .gitignore                   # .terraform/, *.tfstate, *.tfstate.*, .terraform.lock.hcl, *.tfvars
  .tflint.hcl                  # copied from the platform repo
  README.md                    # module list, how to pin, release rules
  spoke/                       # main.tf hub.tf variables.tf outputs.tf versions.tf README.md tests/
```

`terraform/env-dev/main.tf` and `terraform/env-prod/main.tf` in the platform repo: only the
`source` line changes.

```hcl
module "spoke" {
  source = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//spoke?ref=v1.0.0"

  env           = var.env
  address_space = var.address_space
  # ...the rest as before
}
```

## Commands

```bash
# 1. the repo
source ~/.platform-lab/config.env
gh repo create {{GH_OWNER}}/{{MODULES_REPO}} --public --description "Acme Terraform modules"
gh repo clone {{GH_OWNER}}/{{MODULES_REPO}} "$MODULES_DIR"

# 2. the module and its release
cd "$MODULES_DIR"                                    # empty clone: HEAD is an unborn main
cp -r "$LIVE_DIR/terraform/modules/spoke" spoke
cp "$LIVE_DIR/.tflint.hcl" .
mkdir -p .github/workflows && cp ~/.platform-lab/starter/tf-19/ci.yml .github/workflows/
# ...write README.md and .gitignore; update the usage example in spoke/README.md
(cd spoke && terraform init -backend=false && terraform test)
git add -A && git commit -m "spoke module, moved from the platform repo"
git push -u origin main
gh run watch "$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
git tag -a v1.0.0 -m "spoke v1.0.0: the module as extracted in tf-15..tf-18"
git push origin v1.0.0

# 3. the platform repo
cd "$LIVE_DIR" && git switch main && git pull && git switch -c modules-repo
git rm -r terraform/modules
# ...edit the source line in terraform/env-dev/main.tf and terraform/env-prod/main.tf
terraform -chdir=terraform/env-dev init -backend=false && terraform -chdir=terraform/env-dev validate
git add -A && git commit -m "Use the spoke module from {{MODULES_REPO}} v1.0.0"
git push -u origin modules-repo
gh pr create --fill && gh pr checks --watch     # env-dev / env-prod: No changes.
gh pr merge --squash --delete-branch && gh run watch
```

## Verify

```bash
gh api repos/{{GH_OWNER}}/{{MODULES_REPO}}/git/refs/tags/v1.0.0 --jq .ref    # refs/tags/v1.0.0
grep -rn 'source *=' terraform/env-*/                                        # the git:: source, twice
./lab.sh grade
```

## Cost

None in Azure.
