# tf-15 checks (sourced by the grader; cwd = LIVE_DIR)

# Shared helpers: spoke snapshots (also tf-14) and where the spoke module lives (tf-15…tf-20).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-ids.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/spoke-module.sh"
export SPOKE_ZONES
export TF15_SNAP="$LAB_HOME/snapshots/tf-15.ids" TF15_GUIDS="$LAB_HOME/snapshots/tf-15.guids"
# The module call: the local path until tf-19, the modules repo afterwards.
export TF15_SOURCE_RE="source[[:space:]]*=[[:space:]]*\"(\\.\\./modules/spoke|git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//spoke\\?ref=[^\"]+)\""
export TF15_MOVED_RE='to[[:space:]]*=[[:space:]]*module\.spoke\.azurerm_virtual_network\.'
export TF15_STATE_JQ='[.resources[]? | select(.mode == "managed" and .type == "azurerm_virtual_network")] | length == 1 and .[0].module == "module.spoke"'

# tf15_calls_module <stack>: module "spoke" with the right source, and no VNet of its own.
tf15_calls_module() {
  local d="terraform/$1"
  [[ -d "$d" ]] &&
    grep --exclude-dir=.terraform -rqsE "^module[[:space:]]+\"spoke\"" "$d" --include="*.tf" &&
    grep --exclude-dir=.terraform -rqsE "$TF15_SOURCE_RE" "$d" --include="*.tf" &&
    ! grep --exclude-dir=.terraform -rqsE "resource[[:space:]]+\"azurerm_virtual_network\"" "$d" --include="*.tf"
}
# tf15_discovery_skips_modules: run the repo's stacks.sh on a scratch tree in which both a stack
# and a module have a backend block; the stack must be listed, the module never.
tf15_discovery_skips_modules() {
  local t out rc=0
  [[ -f .github/scripts/stacks.sh ]] || return 1
  t="$(mktemp -d)"
  mkdir -p "$t/.github/scripts" "$t/terraform/landing-zone" "$t/terraform/modules/spoke"
  cp .github/scripts/stacks.sh "$t/.github/scripts/"
  printf 'terraform {\n  backend "azurerm" {}\n}\n' | tee "$t/terraform/landing-zone/versions.tf" >"$t/terraform/modules/spoke/versions.tf"
  out="$(cd "$t" && bash .github/scripts/stacks.sh all)" || rc=1
  [[ " $out " == *" landing-zone "* && "$out" != *modules* ]] || rc=1
  rm -rf "$t"
  return "$rc"
}
export -f spoke_collect spoke_expected_ids spoke_ids_unchanged spoke_guids_unchanged spoke_state_jq spoke_module_dir tf15_calls_module tf15_discovery_skips_modules

check_code "the spoke module holds the spoke, with no backend or provider block" \
  'd="$(spoke_module_dir)" && for r in azurerm_resource_group azurerm_virtual_network azurerm_subnet azurerm_virtual_network_peering azurerm_private_dns_zone_virtual_network_link; do grep -qsE "^resource[[:space:]]+\"$r\"" "$d"/*.tf || exit 1; done && ! grep -qsE "^[[:space:]]*(backend|provider)[[:space:]]+\"" "$d"/*.tf' \
  "terraform/modules/spoke must declare the resource group, VNet, subnets, both peerings and the DNS links, and no backend or provider block (the calling stack configures those)"

check_code "env-dev and env-prod call module \"spoke\" and declare no VNet themselves" \
  'tf15_calls_module env-dev && tf15_calls_module env-prod' \
  "each env stack needs module \"spoke\" { source = \"../modules/spoke\" ... } and no azurerm_virtual_network resource of its own"

check_code "moved blocks move the spoke into module.spoke in both env stacks" \
  'for s in env-dev env-prod; do grep --exclude-dir=.terraform -rqsE "^[[:space:]]*moved[[:space:]]*\{" "terraform/$s" --include="*.tf" && grep --exclude-dir=.terraform -rqsE "$TF15_MOVED_RE" "terraform/$s" --include="*.tf" || exit 1; done' \
  "terraform/env-dev and terraform/env-prod need moved blocks, at least from azurerm_virtual_network.spoke to module.spoke.azurerm_virtual_network.<name> (keep them after the merge)"

check_code "stack discovery never lists terraform/modules" \
  'tf15_discovery_skips_modules' \
  ".github/scripts/stacks.sh must skip everything under terraform/modules/, even a module with a backend block (tried on a scratch tree)"

check "env-dev and env-prod states hold their VNet inside module.spoke" \
  'spoke_state_jq env-dev.tfstate "$TF15_STATE_JQ" && spoke_state_jq env-prod.tfstate "$TF15_STATE_JQ"' \
  "env-dev.tfstate / env-prod.tfstate must manage one VNet, at module.spoke (has the pipeline applied the merge?)"

check "every spoke resource still exists with the same ID" \
  'spoke_ids_unchanged "$TF15_SNAP"' \
  "a resource from $TF15_SNAP (or the expected spoke resources) no longer exists under its ID: was something destroyed or renamed?"

check "the spoke VNets were not recreated (resourceGuid unchanged)" \
  'spoke_guids_unchanged "$TF15_GUIDS"' \
  "VNet was recreated (resourceGuid changed): the extraction must not destroy anything (baseline: $TF15_GUIDS)"
