#!/usr/bin/env bash
# tf-02 catchup (after-push, cwd = LIVE_DIR): apply terraform/bootstrap with LOCAL state.
# The tree may already be a later task's reference whose bootstrap has the azurerm backend
# (tf-03); then the state account may not exist yet, so apply once with a temporary local-backend
# override and let tf-03's catchup migrate the state. Idempotent.
set -euo pipefail

cd terraform/bootstrap
rg="rg-$PREFIX-tfstate" sa="st${PREFIX}tfstate$SUFFIX"

has_backend() { grep --exclude-dir=.terraform -rqsE 'backend[[:space:]]+"azurerm"' --include='*.tf' --exclude='*_override.tf' .; }
account_exists() { az storage account show -g "$rg" -n "$sa" --query id -o tsv >/dev/null 2>&1; }

if ! has_backend; then
  # Plain local state (catchup to tf-02 itself). -migrate-state copies a remote state back down
  # if this repo was further along before; otherwise it is an ordinary init.
  terraform init -input=false -migrate-state -force-copy </dev/null
  terraform apply -auto-approve -input=false </dev/null
  exit 0
fi

if account_exists; then
  echo "tf-02: $sa exists; state is handled by tf-03's catchup"
  exit 0
fi

override=zz_catchup_local_override.tf
trap 'rm -f "$override"' EXIT
printf 'terraform {\n  backend "local" {}\n}\n' >"$override"
terraform init -input=false -reconfigure </dev/null
terraform apply -auto-approve -input=false </dev/null
