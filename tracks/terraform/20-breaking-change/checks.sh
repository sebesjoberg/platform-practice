# tf-20 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

export TF20_LIVE="$GH_OWNER/$LIVE_REPO" TF20_MODS="$GH_OWNER/$MODULES_REPO"
export TF20_SRC="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//spoke\\?ref="
export TF20_FILES_JQ='.[] | select(.type == "file" and (.name | endswith(".tf"))) | .path'

# tf20_tag_has <tag> <ERE>: some spoke/*.tf at <tag> in the modules repo matches <ERE>.
# grep -c reads all of gh's output (grep -q could close the pipe early under pipefail).
tf20_tag_has() {
  local f
  for f in $(gh api "repos/$TF20_MODS/contents/spoke?ref=$1" --jq "$TF20_FILES_JQ"); do
    if gh api -H "Accept: application/vnd.github.raw" "repos/$TF20_MODS/contents/$f?ref=$1" | grep -cE "$2" >/dev/null; then
      return 0
    fi
  done
  return 1
}
# tf20_pin <stack dir>: the newest spoke release tag (vX.Y.Z) the stack pins, empty if none.
tf20_pin() {
  { grep -rhoE "${TF20_SRC}v[0-9]+\.[0-9]+\.[0-9]+\"" "$1" --include="*.tf" || true; } |
    grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | sort -V | tail -n 1
}
export -f tf20_tag_has tf20_pin

check_code "the spoke module's address input is renamed to vnet_cidr" \
  '[[ -n "${MODULES_DIR:-}" ]] && grep -qsE "^variable[[:space:]]+\"vnet_cidr\"" "$MODULES_DIR"/spoke/*.tf && ! grep -qsE "^variable[[:space:]]+\"address_space\"" "$MODULES_DIR"/spoke/*.tf' \
  "in $MODULES_DIR/spoke: rename variable \"address_space\" to \"vnet_cidr\" (and every var.address_space, the tests and the README)"

check_code "CHANGELOG.md has a 2.0.0 entry that explains the migration" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && [[ -f "$c" ]] && grep -qE "^#+[^0-9]*v?2\.0\.0" "$c" && grep -qF address_space "$c" && grep -qF vnet_cidr "$c"' \
  "add CHANGELOG.md to the root of $MODULES_REPO with a \"## 2.0.0\" heading that says address_space is now vnet_cidr and what callers change"

# Canary order: dev pins spoke v2 (or later) with vnet_cidr; prod pins a release that is not newer
# than dev's. Right after tf-20 that is v1.0.0; prod catches up in tf-24.
check_code "env-dev runs spoke v2 with vnet_cidr, env-prod pins a release not newer than dev's" \
  'dev="$(tf20_pin terraform/env-dev)" && prod="$(tf20_pin terraform/env-prod)" && [[ "$dev" =~ ^v([0-9]+)\. ]] && ((BASH_REMATCH[1] >= 2)) && grep -rqsE "^[[:space:]]*vnet_cidr[[:space:]]*=" terraform/env-dev --include="*.tf" && [[ -n "$prod" && "$(printf "%s\n%s\n" "$prod" "$dev" | sort -V | tail -n 1)" == "$dev" ]]' \
  "terraform/env-dev: spoke ?ref=v2.0.0 and vnet_cidr = ...; terraform/env-prod: stays on ?ref=v1.0.0 with address_space until dev has proven v2 (never ahead of dev)"

check "tag v2.0.0 exists in $TF20_MODS" \
  '[[ "$(gh api "repos/$TF20_MODS/git/refs/tags/v2.0.0" --jq .ref)" == refs/tags/v2.0.0 ]]' \
  "tag the release and push it: git tag -a v2.0.0 -m \"spoke v2.0.0\" && git push origin v2.0.0"

check "v2.0.0 has vnet_cidr instead of address_space; v1.0.0 is unchanged" \
  'tf20_tag_has v2.0.0 "^variable[[:space:]]+\"vnet_cidr\"" && ! tf20_tag_has v2.0.0 "^variable[[:space:]]+\"address_space\"" && tf20_tag_has v1.0.0 "^variable[[:space:]]+\"address_space\""' \
  "spoke/ at v2.0.0 must declare variable \"vnet_cidr\" and no \"address_space\"; v1.0.0 must still declare \"address_space\" (never move a released tag)"

check "the latest terraform run on main succeeded" \
  'ci_main_green "$TF20_LIVE"' \
  "the newest completed terraform.yml run on main in $TF20_LIVE is not green (merged? is v2.0.0 pushed?)"
