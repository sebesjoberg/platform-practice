# tf-03 checks (sourced by the grader; cwd = LIVE_DIR)

check_code "bootstrap uses the azurerm backend with Entra ID auth" \
  'grep -rqsE "backend[[:space:]]+\"azurerm\"" terraform/bootstrap --include="*.tf" && grep -rqsE "use_azuread_auth[[:space:]]*=[[:space:]]*true" terraform/bootstrap --include="*.tf"' \
  "terraform/bootstrap needs backend \"azurerm\" with use_azuread_auth = true"

check_code "backend points at st${PREFIX}tfstate$SUFFIX / tfstate / bootstrap.tfstate" \
  'grep -rqsE "storage_account_name[[:space:]]*=[[:space:]]*\"st${PREFIX}tfstate$SUFFIX\"" terraform/bootstrap --include="*.tf" && grep -rqsE "container_name[[:space:]]*=[[:space:]]*\"tfstate\"" terraform/bootstrap --include="*.tf" && grep -rqsE "key[[:space:]]*=[[:space:]]*\"bootstrap\.tfstate\"" terraform/bootstrap --include="*.tf"' \
  "backend must use storage_account_name st${PREFIX}tfstate$SUFFIX, container_name tfstate, key bootstrap.tfstate"

check "blob bootstrap.tfstate exists in the tfstate container" \
  '[[ "$(az storage blob exists --auth-mode login --account-name "st${PREFIX}tfstate$SUFFIX" -c tfstate -n bootstrap.tfstate --query exists -o tsv)" == true ]]' \
  "no bootstrap.tfstate blob in st${PREFIX}tfstate$SUFFIX/tfstate; run terraform init -migrate-state"

check "no state file in git history" \
  '[[ -z "$(git log --all --oneline -- "*.tfstate" "*.tfstate.*")" ]]' \
  "git log --all -- '*.tfstate' '*.tfstate.*' lists commits; a state file was committed"

check "no leftover local state files in the working tree" \
  '[[ -z "$(find terraform -name "*.tfstate*" -not -path "*/.terraform/*" -print -quit)" ]]' \
  "delete the stale terraform.tfstate / terraform.tfstate.backup files under terraform/"
