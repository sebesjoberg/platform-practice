# tf-30 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

export TF30_REPO="$GH_OWNER/$LIVE_REPO" TF30_MODS="$GH_OWNER/$MODULES_REPO"
export TF30_DEPENDABOT=.github/dependabot.yml
export TF30_SRC_RE="git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//[^?\"]+\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+"

# tf30_stacks: every stack directory (a backend "azurerm" block), bootstrap included, relative.
tf30_stacks() {
  grep -rlE --include='*.tf' 'backend[[:space:]]+"azurerm"' terraform 2>/dev/null |
    grep -v '/\.terraform/' | xargs -r -n1 dirname | grep -vE '^terraform/modules(/|$)' | sort -u
}
# tf30_all_stacks <test> : <test> <dir> holds for every stack, and there is at least one.
tf30_all_stacks() {
  local s n=0
  for s in $(tf30_stacks); do
    "$1" "$s" || return 1
    n=$((n + 1))
  done
  [[ $n -gt 0 ]]
}
# tf30_pin5 <dir>: azurerm pinned with ~> 5.x.
tf30_pin5() {
  awk '/source[[:space:]]*=[[:space:]]*"hashicorp\/azurerm"/ { a = 1; next } a && /version[[:space:]]*=/ { print; exit }' "$1"/*.tf |
    grep -qE '"~>[[:space:]]*5\.[0-9]+'
}
# tf30_lock <dir>: .terraform.lock.hcl locks azurerm 5.x, and every provider in it has at least two
# h1: hashes (one per platform locked: linux_amd64 and windows_amd64).
tf30_lock() {
  local f="$1/.terraform.lock.hcl"
  [[ -f "$f" ]] || return 1
  awk '/^provider "registry.terraform.io\/hashicorp\/azurerm"/ { a = 1; next } a && /version[[:space:]]*=/ { print; exit }' "$f" |
    grep -qE '"5\.' || return 1
  awk '/^provider "/ { if (p && n < 2) bad = 1; p = 1; n = 0; next } p && /"h1:/ { n++ }
    END { if (p && n < 2) bad = 1; exit (bad || !p) }' "$f"
}
# tf30_dependabot_covers <dir>: dependabot.yml's terraform entry names the directory (or a glob
# that covers it).
tf30_dependabot_covers() {
  local d="/$1" up
  up="$(dirname "$d")"
  grep -qE "^[[:space:]]*-?[[:space:]]*(directory:)?[[:space:]]*\"?($d|$up/\\*|/terraform/\\*\\*)\"?[[:space:]]*(#.*)?$" "$TF30_DEPENDABOT"
}
# tf30_modules5: every module in the modules repo requires azurerm >= 5.x, capped below 6.0.
tf30_modules5() {
  local f n=0
  [[ -n "${MODULES_DIR:-}" ]] || return 1
  for f in "$MODULES_DIR"/*/versions.tf; do
    [[ -f "$f" ]] || continue
    awk '/source[[:space:]]*=[[:space:]]*"hashicorp\/azurerm"/ { a = 1; next } a && /version[[:space:]]*=/ { print; exit }' "$f" |
      grep -E '>=[[:space:]]*5\.' | grep -qE '<[[:space:]]*6(\.0)*[[:space:]]*(,|")' || return 1
    n=$((n + 1))
  done
  [[ $n -gt 0 ]]
}
export -f tf30_stacks tf30_all_stacks tf30_pin5 tf30_lock tf30_dependabot_covers tf30_modules5

check_code "every stack pins azurerm ~> 5.x" \
  'tf30_all_stacks tf30_pin5' \
  "every stack under terraform/ (bootstrap too) needs azurerm version = \"~> 5.14\""

check_code "every stack commits a lock file for azurerm 5.x with hashes for two platforms" \
  'tf30_all_stacks tf30_lock' \
  "commit terraform/<stack>/.terraform.lock.hcl in every stack: terraform providers lock -platform=linux_amd64 -platform=windows_amd64 (two h1: hashes per provider)"

check_code "every module requires azurerm >= 5.x, < 6.0" \
  'tf30_modules5' \
  "every module's versions.tf in $MODULES_REPO needs azurerm version = \">= 5.14, < 6.0\""

check_code "the DNS zone links name their zone by ID (azurerm 5.0)" \
  '! grep -rqsE "^[[:space:]]*private_dns_zone_name[[:space:]]*=" terraform "${MODULES_DIR:-/nonexistent}" --include="*.tf" && grep -rqsE "^[[:space:]]*private_dns_zone_id[[:space:]]*=" terraform/landing-zone --include="*.tf" && grep -qsE "^[[:space:]]*private_dns_zone_id[[:space:]]*=" "${MODULES_DIR:-/nonexistent}"/spoke/*.tf' \
  "azurerm_private_dns_zone_virtual_network_link takes private_dns_zone_id in 5.x (landing-zone's hub links and the spoke module); private_dns_zone_name and resource_group_name are gone"

check_code "CHANGELOG.md has a 3.0.0 entry for the move to azurerm 5" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && [[ -f "$c" ]] && grep -qE "^#+[^0-9]*v?3\.0\.0" "$c" && grep -qiE "azurerm[^0-9]*5" "$c" && grep -qF private_dns_zone_ids "$c"' \
  "add a \"## 3.0.0\" entry to $MODULES_REPO/CHANGELOG.md: azurerm 5.x is required and spoke takes private_dns_zone_ids; say what callers change"

check_code "every module source pins v3 or later" \
  'refs="$(grep -rhoE "$TF30_SRC_RE" terraform --include="*.tf" | sed -E "s/.*ref=v([0-9]+).*/\1/")" && [[ -n "$refs" ]] && ! grep -qvE "^([3-9]|[1-9][0-9]+)$" <<<"$refs"' \
  "every module source in terraform/ must pin ?ref=v3.0.0 (or later): a v2.x module caps azurerm below 5.0 and terraform init fails"

check_code "dependabot.yml updates terraform (providers and module refs) in every stack" \
  '[[ -f "$TF30_DEPENDABOT" ]] && grep -qE "package-ecosystem:[[:space:]]*\"?terraform\"?" "$TF30_DEPENDABOT" && tf30_all_stacks tf30_dependabot_covers' \
  "$TF30_DEPENDABOT needs a package-ecosystem: terraform entry whose directories list every stack (/terraform/bootstrap, /terraform/landing-zone, ...)"

check "tag v3.0.0 exists in $TF30_MODS and its spoke needs azurerm 5" \
  'gh api -H "Accept: application/vnd.github.raw" "repos/$TF30_MODS/contents/spoke/versions.tf?ref=v3.0.0" | grep -qE ">=[[:space:]]*5\.[0-9]+"' \
  "tag the release and push it: git tag -a v3.0.0 -m \"v3.0.0: azurerm 5.x\" && git push origin v3.0.0"

check "Dependabot has the secrets BUDGET_EMAIL and LEARNER_IP" \
  's="$(gh api "repos/$TF30_REPO/dependabot/secrets?per_page=100" --jq ".secrets[].name")" && grep -qx BUDGET_EMAIL <<<"$s" && grep -qx LEARNER_IP <<<"$s"' \
  "gh secret set --app dependabot BUDGET_EMAIL -R $TF30_REPO --body <your email>, and the same for LEARNER_IP: Dependabot PRs get no Actions secrets"

check "latest completed terraform run on main succeeded" \
  'ci_main_green "$TF30_REPO"' \
  "the newest completed terraform.yml run on main is not green; open it in the Actions tab"
