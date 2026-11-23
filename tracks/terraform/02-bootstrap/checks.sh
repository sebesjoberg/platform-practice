# tf-02 checks (sourced by the grader; cwd = LIVE_DIR)

export TF02_RG="rg-$PREFIX-tfstate" TF02_SA="st${PREFIX}tfstate$SUFFIX"
export TF02_TAGS_JQ='.location == env.LOCATION and .tags.owner == env.OWNER_TAG and .tags.env == "platform" and .tags.managed_by == "terraform"'
export TF02_SA_JQ='.location == env.LOCATION and .sku.name == "Standard_LRS" and .kind == "StorageV2" and .minimumTlsVersion == "TLS1_2" and .enableHttpsTrafficOnly == true and .allowBlobPublicAccess == false'
export TF02_BLOB_JQ='.isVersioningEnabled == true and .deleteRetentionPolicy.enabled == true and .deleteRetentionPolicy.days == 7 and .containerDeleteRetentionPolicy.enabled == true and .containerDeleteRetentionPolicy.days == 7'

check_code "bootstrap pins required_version and azurerm ~> 4.x" \
  'grep -rqsE "required_version[[:space:]]*=" terraform/bootstrap --include="*.tf" && grep -rqsE "version[[:space:]]*=[[:space:]]*\"~>[[:space:]]*4\.[0-9]+" terraform/bootstrap --include="*.tf"' \
  "terraform/bootstrap needs required_version and an azurerm version constraint \"~> 4.81\""

check_code "bootstrap provider sets subscription_id" \
  'grep -rqsE "subscription_id[[:space:]]*=" terraform/bootstrap --include="*.tf"' \
  "the azurerm provider block in terraform/bootstrap must set subscription_id"

check_code "storage account is declared with shared key access disabled" \
  'grep -rqsE "shared_access_key_enabled[[:space:]]*=[[:space:]]*false" terraform/bootstrap --include="*.tf"' \
  "no shared_access_key_enabled = false in terraform/bootstrap"

check "$TF02_RG exists in $LOCATION with the required tags" \
  'az group show -n "$TF02_RG" -o json | jq -e "$TF02_TAGS_JQ"' \
  "expected $TF02_RG in $LOCATION with tags owner=$OWNER_TAG, env=platform, managed_by=terraform"

check "$TF02_SA has shared key access disabled" \
  '[[ "$(az storage account show -g "$TF02_RG" -n "$TF02_SA" --query allowSharedKeyAccess -o tsv)" == false ]]' \
  "allowSharedKeyAccess of $TF02_SA must be false"

check "$TF02_SA is Standard_LRS StorageV2 with TLS 1.2, HTTPS only, no public blob access" \
  'az storage account show -g "$TF02_RG" -n "$TF02_SA" -o json | jq -e "$TF02_SA_JQ"' \
  "$TF02_SA in $LOCATION: Standard_LRS, StorageV2, minimumTlsVersion TLS1_2, HTTPS only, allowBlobPublicAccess false"

check "$TF02_SA has blob versioning and 7-day blob and container soft delete" \
  'az storage account blob-service-properties show -g "$TF02_RG" --account-name "$TF02_SA" -o json | jq -e "$TF02_BLOB_JQ"' \
  "blob service of $TF02_SA: versioning on, delete retention 7 days, container delete retention 7 days"

check "private container tfstate exists" \
  '[[ "$(az storage container-rm show -g "$TF02_RG" --storage-account "$TF02_SA" -n tfstate --query publicAccess -o tsv)" == None ]]' \
  "expected a container tfstate with public access None in $TF02_SA"

check "you have a blob data role on $TF02_SA" \
  'me="$(az ad signed-in-user show --query id -o tsv)" && [[ -n "$me" ]] && id="$(az storage account show -g "$TF02_RG" -n "$TF02_SA" --query id -o tsv)" && [[ -n "$id" ]] && az role assignment list --assignee "$me" --scope "$id" --include-inherited --query "[].roleDefinitionName" -o tsv | grep -Eqx "Storage Blob Data (Contributor|Owner)"' \
  "your user needs Storage Blob Data Contributor on $TF02_SA (shared keys are off, Owner is not a data role)"
