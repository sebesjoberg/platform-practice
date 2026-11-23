# tf-07 checks (sourced by the grader; cwd = LIVE_DIR)

# Prints every `variable "<name>" { ... }` block (name is an ERE) in the .tf files under <dir>.
# Relies on terraform fmt layout: the block ends with a "}" in column 1.
export TF07_BLOCK_AWK='$0 ~ re { on = 1 } on { print } on && /^}/ { on = 0 }'
tf07_var_block() { # tf07_var_block <dir> <name-ere>
  find "$1" -name "*.tf" -not -path "*/.terraform/*" -exec awk -v re="^variable[[:space:]]+\"($2)\"" "$TF07_BLOCK_AWK" {} +
}
export TF07_TAGS_JQ='.location == env.LOCATION and .tags.owner == env.OWNER_TAG and .tags.env == "hub" and .tags.managed_by == "terraform"'
export -f tf07_var_block

# Searches all stacks: from tf-14 on the per-environment stacks carry `variable "env"`.
check_code "an env variable is validated to dev and prod" \
  'b="$(tf07_var_block terraform "envs?")" && grep -q "validation" <<<"$b" && grep -q "\"dev\"" <<<"$b" && grep -q "\"prod\"" <<<"$b"' \
  "declare variable \"envs\" (a set of environments) with a validation block that allows only \"dev\" and \"prod\""

check_code "landing-zone validates prefix and location (swedencentral)" \
  'p="$(tf07_var_block terraform/landing-zone prefix)" && l="$(tf07_var_block terraform/landing-zone location)" && grep -q "validation" <<<"$p" && grep -q "validation" <<<"$l" && grep -q "swedencentral" <<<"$l"' \
  "terraform/landing-zone needs variable \"prefix\" and variable \"location\", each with a validation block (location: swedencentral only)"

check_code "landing-zone tags come from locals built on var.owner" \
  'grep --exclude-dir=.terraform -rqsE "^[[:space:]]*locals[[:space:]]*\{" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "owner[[:space:]]*=[[:space:]]*var\.owner" terraform/landing-zone --include="*.tf" && grep --exclude-dir=.terraform -rqsE "managed_by[[:space:]]*=[[:space:]]*\"terraform\"" terraform/landing-zone --include="*.tf"' \
  "build the tags in a locals block with owner = var.owner, env and managed_by = \"terraform\""

check "rg-$PREFIX-hub still has the required tags" \
  'az group show -n "rg-$PREFIX-hub" -o json | jq -e "$TF07_TAGS_JQ"' \
  "rg-$PREFIX-hub must keep location $LOCATION and tags owner=$OWNER_TAG, env=hub, managed_by=terraform (a refactor changes nothing in Azure)"
