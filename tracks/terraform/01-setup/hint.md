# tf-01 hints

Docs:
- Terraform install (Linux, apt or zip): https://developer.hashicorp.com/terraform/install
- Azure CLI on Linux: https://learn.microsoft.com/cli/azure/install-azure-cli-linux
- gh on Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- gitignore patterns: https://git-scm.com/docs/gitignore

Traps:
- **The Windows `az` leaks into WSL.** WSL appends the Windows PATH, so `which az` can show
  `/mnt/c/Program Files/.../az`. Install the Linux build, then check `type -a az` and make
  sure a Linux path comes first. The same goes for `terraform`.
- **Wrong subscription.** `az login` picks a default subscription that may be your
  employer's. Run `az account list -o table`, then `az account set -s <id>`, *before*
  `./lab.sh init`. Init records whatever `az account show` says.
- **`*.tfstate*` vs. `*.tfstate` + `*.tfstate.*`.** Both work. Just make sure backups such
  as `terraform.tfstate.backup` and `terraform.tfstate.1700000000.backup` are ignored too.
- **Don't ignore `.terraform.lock.hcl`.** Some templates on the internet do. Lock files
  belong in Git (you'll commit them from tf-30).
- **`*.tfvars*` is too greedy.** It also hides `*.auto.tfvars.example`, which is meant to
  be committed.
- Test your patterns without committing anything:
  `git check-ignore -v terraform/bootstrap/terraform.tfstate`.
