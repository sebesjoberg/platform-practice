# tf-19 hints

Docs:
- Module sources: generic Git, `//subdir` and `?ref=`: https://developer.hashicorp.com/terraform/language/modules/sources#generic-git-repository
- Publishing modules and versioning: https://developer.hashicorp.com/terraform/language/modules/develop/publish
- Annotated tags: https://git-scm.com/book/en/v2/Git-Basics-Tagging
- `gh repo create`: https://cli.github.com/manual/gh_repo_create

Traps:
- **No `moved` blocks this time.** The state address of every resource stays
  `module.spoke.<…>`: it depends on the module block's name, not on where its source lives.
  Changing `source` from a path to a Git URL only changes where `terraform init` fetches the
  code. The plan is `No changes.` as long as the code at `v1.0.0` is the code you had locally.
- **Order matters.** Tag and push `v1.0.0` *before* opening the live PR: the plan job runs
  `terraform init`, which clones the module at that tag. A missing tag fails the plan with a
  git error.
- **`//spoke` is the subdirectory, `?ref=` the version.** The `.git` before `//` is required for
  `git::https://` sources. The `?ref=` goes at the very end.
- **Public repo, no credentials.** CI clones the module anonymously over HTTPS. A private
  modules repo would need a token or deploy key in the platform repo's workflow.
- **Tags are forever.** Stacks pin `v1.0.0`; moving that tag later would change them without a
  pull request. Fix a bad release with `v1.0.1`, never by moving `v1.0.0`.
- **Local runs:** after changing `source`, run `terraform init -upgrade` (or plain `init`) in
  the stack: Terraform caches modules in `.terraform/modules` and tells you "Module source has
  changed".
- **The live workflow's test step finds nothing now** (no `terraform/modules`), which is fine:
  the module's tests run in the modules repo's CI. tflint and trivy in the platform repo still
  cover the stacks.
- **Lock files stay out of the modules repo.** A module doesn't choose provider versions; the
  calling stack does (it gets its lock file in tf-30).
