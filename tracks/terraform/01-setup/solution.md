# tf-01 solution

## Tools (WSL Ubuntu)

```bash
# Terraform from HashiCorp's apt repo
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform jq git

# Azure CLI (Linux build)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# gh: follow https://github.com/cli/cli/blob/trunk/docs/install_linux.md, then
gh auth login          # GitHub.com, HTTPS, "authenticate Git with your GitHub credentials": yes

type -a az terraform   # the first hit must not be under /mnt/c
terraform version      # 1.17 or newer
```

## Azure and lab config

```bash
az login
az account list -o table
az account set --subscription <subscription id>
./lab.sh init          # asks for prefix, GitHub owner and owner tag
./lab.sh next          # starts tf-01 and shows the task with your names
```

## Repo

```bash
mkdir -p ~/acme && cd ~/acme
gh repo create {{GH_OWNER}}/{{LIVE_REPO}} --public --clone
cd {{LIVE_REPO}}
```

`.gitignore`:

```gitignore
# Terraform working directories (any depth)
.terraform/

# State and state backups never go to Git
*.tfstate
*.tfstate.*

# Variable files may hold secrets; commit *.auto.tfvars.example instead
*.tfvars
*.tfvars.json

# Crash logs, plan files and CLI override files
crash.log
crash.*.log
*.tfplan
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

`.terraform.lock.hcl` is deliberately *not* in the list.

```bash
git check-ignore -v terraform/bootstrap/terraform.tfstate.backup   # matched by *.tfstate.*
git check-ignore -v x.auto.tfvars.example || echo "not ignored (good)"
git add .gitignore && git commit -m "Ignore Terraform state, working dirs and tfvars"
git push -u origin main
```

## Verify

```bash
gh repo view {{GH_OWNER}}/{{LIVE_REPO}} --json visibility   # "PUBLIC"
./lab.sh grade
```

Cost: nothing in Azure yet.
