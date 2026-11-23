# tf-20 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

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
export -f tf20_tag_has

check_code "the spoke module's address input is renamed to vnet_cidr" \
  '[[ -n "${MODULES_DIR:-}" ]] && grep -qsE "^variable[[:space:]]+\"vnet_cidr\"" "$MODULES_DIR"/spoke/*.tf && ! grep -qsE "^variable[[:space:]]+\"address_space\"" "$MODULES_DIR"/spoke/*.tf' \
  "in $MODULES_DIR/spoke: rename variable \"address_space\" to \"vnet_cidr\" (and every var.address_space, the tests and the README)"

check_code "CHANGELOG.md has a 2.0.0 entry that explains the migration" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && [[ -f "$c" ]] && grep -qE "^#+[^0-9]*v?2\.0\.0" "$c" && grep -qF address_space "$c" && grep -qF vnet_cidr "$c"' \
  "add CHANGELOG.md to the root of $MODULES_REPO with a \"## 2.0.0\" heading that says address_space is now vnet_cidr and what callers change"

check_code "env-dev runs v2.0.0 with vnet_cidr, env-prod stays on v1" \
  'grep -rqsE "${TF20_SRC}v2\.0\.0\"" terraform/env-dev --include="*.tf" && grep -rqsE "^[[:space:]]*vnet_cidr[[:space:]]*=" terraform/env-dev --include="*.tf" && grep -rqsE "${TF20_SRC}v1\.[0-9]+\.[0-9]+\"" terraform/env-prod --include="*.tf" && ! grep -rqsE "^[[:space:]]*vnet_cidr[[:space:]]*=" terraform/env-prod --include="*.tf"' \
  "terraform/env-dev: ?ref=v2.0.0 and vnet_cidr = ...; terraform/env-prod: unchanged on ?ref=v1.0.0 with address_space (prod follows later)"

check "tag v2.0.0 exists in $TF20_MODS" \
  '[[ "$(gh api "repos/$TF20_MODS/git/refs/tags/v2.0.0" --jq .ref)" == refs/tags/v2.0.0 ]]' \
  "tag the release and push it: git tag -a v2.0.0 -m \"spoke v2.0.0\" && git push origin v2.0.0"

check "v2.0.0 has vnet_cidr instead of address_space; v1.0.0 is unchanged" \
  'tf20_tag_has v2.0.0 "^variable[[:space:]]+\"vnet_cidr\"" && ! tf20_tag_has v2.0.0 "^variable[[:space:]]+\"address_space\"" && tf20_tag_has v1.0.0 "^variable[[:space:]]+\"address_space\""' \
  "spoke/ at v2.0.0 must declare variable \"vnet_cidr\" and no \"address_space\"; v1.0.0 must still declare \"address_space\" (never move a released tag)"

check "the latest terraform run on main succeeded" \
  '[[ "$(gh api "repos/$TF20_LIVE/actions/workflows/terraform.yml/runs?branch=main&status=completed&per_page=1" --jq ".workflow_runs[0].conclusion")" == success ]]' \
  "the newest completed terraform.yml run on main in $TF20_LIVE is not green (merged? is v2.0.0 pushed?)"
