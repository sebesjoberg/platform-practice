# tf-16 checks (sourced by the grader; cwd = LIVE_DIR)

# Where the spoke module lives (terraform/modules/spoke, or $MODULES_DIR/spoke from tf-19).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-module.sh"
export TF16_REPO="$GH_OWNER/$LIVE_REPO" TF16_MOD_REPO="$GH_OWNER/$MODULES_REPO"

# tf16_names <dir> <kind>: names of the top-level <kind> blocks.
tf16_names() { awk -v kind="$2" '$1 == kind && $2 ~ /^"/ { n = $2; gsub(/"/, "", n); print n }' "$1"/*.tf; }
# tf16_readme_lists_all <dir>: README.md has the terraform-docs markers and every input and output
# name between them (backslash escapes removed, as terraform-docs writes address\_space).
tf16_readme_lists_all() {
  local d=$1 r="$1/README.md" sect n
  [[ -f "$r" ]] && grep -q '<!-- BEGIN_TF_DOCS -->' "$r" && grep -q '<!-- END_TF_DOCS -->' "$r" || return 1
  sect="$(sed -n '/<!-- BEGIN_TF_DOCS -->/,/<!-- END_TF_DOCS -->/p' "$r" | tr -d '\134')" # \134 = backslash
  for n in $(tf16_names "$d" variable) $(tf16_names "$d" output); do
    grep -qw -- "$n" <<<"$sect" || return 1
  done
}
# tf16_capped_lower_bound <dir>: a provider version constraint with a >= lower bound and a < 5
# cap, in either order (">= 4.81, < 5.0" or "< 5.0, >= 4.81").
tf16_capped_lower_bound() {
  grep -hE '^[[:space:]]+version[[:space:]]*=[[:space:]]*"' "$1"/*.tf |
    grep -E '>=[[:space:]]*[0-9]' | grep -qE '<[[:space:]]*5(\.0)*[[:space:]]*(,|")'
}
export -f spoke_module_dir tf_blocks_missing tf_block tf16_names tf16_readme_lists_all tf16_capped_lower_bound

check_code "every input and output of the spoke module has a description" \
  'd="$(spoke_module_dir)" && [[ -n "$(tf16_names "$d" output)" ]] && [[ -z "$(tf_blocks_missing "$d" variable description)$(tf_blocks_missing "$d" output description)" ]]' \
  "give every variable and output in the spoke module a description (missing: run terraform-docs and look for empty Description cells)"

check_code "the module outputs resource_group_name, vnet_id, vnet_name and subnet_ids" \
  'd="$(spoke_module_dir)" && for o in resource_group_name vnet_id vnet_name subnet_ids; do grep -qsE "^output[[:space:]]+\"$o\"" "$d"/*.tf || exit 1; done' \
  "add the outputs resource_group_name, vnet_id, vnet_name and subnet_ids (a map by short name: app, pe, aca)"

check_code "env and the address space input are validated" \
  'd="$(spoke_module_dir)" && tf_block "$d" variable env | grep -qE "^[[:space:]]+validation[[:space:]]*\{" && { tf_block "$d" variable address_space; tf_block "$d" variable vnet_cidr; } | grep -qE "^[[:space:]]+validation[[:space:]]*\{"' \
  "add validation blocks to variable \"env\" (dev or prod) and variable \"address_space\" (a /16 CIDR block)"

check_code "the module states lower bounds (>=) for Terraform and azurerm (capped below 5.0), no ~>" \
  'd="$(spoke_module_dir)" && grep -qsE "required_version[[:space:]]*=[[:space:]]*\">=" "$d"/*.tf && tf16_capped_lower_bound "$d" && ! grep -qsE "^[[:space:]]*(required_version|version)[[:space:]]*=.*~>" "$d"/*.tf' \
  "in the module: required_version = \">= 1.17\" and azurerm version = \">= 4.81, < 5.0\" (a lower bound, capped below the next major); the stacks keep their ~> pins"

check_code "the module README has a terraform-docs section listing every input and output" \
  'tf16_readme_lists_all "$(spoke_module_dir)"' \
  "README.md next to the module needs <!-- BEGIN_TF_DOCS --> / <!-- END_TF_DOCS --> with every input and output between them: terraform-docs markdown table --output-file README.md --output-mode inject ."

check "the module README is merged to main on GitHub" \
  'gh api "repos/$TF16_REPO/contents/terraform/modules/spoke/README.md?ref=main" --jq .name >/dev/null 2>&1 || gh api "repos/$TF16_MOD_REPO/contents/spoke/README.md?ref=main" --jq .name >/dev/null' \
  "no terraform/modules/spoke/README.md on main in $TF16_REPO: merge the PR"
