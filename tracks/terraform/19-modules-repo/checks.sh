# tf-19 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

export TF19_LIVE="$GH_OWNER/$LIVE_REPO" TF19_MODS="$GH_OWNER/$MODULES_REPO"
# A spoke source in the modules repo, pinned to a release tag vX.Y.Z (env-dev moves to v2 in
# tf-20, so the version isn't fixed here; the tag check below wants v1.0.0).
export TF19_SOURCE_RE="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//spoke\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+\""
export TF19_LOCAL_RE='source[[:space:]]*=[[:space:]]*"(\.\.?/)+modules/'

check_code "the modules repo holds the spoke module with its tests and README" \
  '[[ -n "${MODULES_DIR:-}" && -d "$MODULES_DIR/spoke" ]] && grep -qsE "^resource[[:space:]]+\"azurerm_virtual_network\"" "$MODULES_DIR"/spoke/*.tf && compgen -G "$MODULES_DIR/spoke/tests/*.tftest.hcl" >/dev/null && [[ -f "$MODULES_DIR/spoke/README.md" ]]' \
  "expected the module in $MODULES_DIR/spoke (the .tf files, tests/ and README.md, moved from terraform/modules/spoke)"

check_code "env-dev and env-prod use the spoke module from the modules repo by tag" \
  'for s in env-dev env-prod; do grep -rqsE "$TF19_SOURCE_RE" "terraform/$s" --include="*.tf" || exit 1; done' \
  "each env stack needs source = \"git::https://github.com/$GH_OWNER/$MODULES_REPO.git//spoke?ref=v1.0.0\""

check_code "no local module sources and no terraform/modules left in the live repo" \
  '! grep -rqsE "$TF19_LOCAL_RE" terraform --include="*.tf" && [[ -z "$(find terraform/modules -name "*.tf" 2>/dev/null)" ]]' \
  "delete terraform/modules/spoke from $LIVE_REPO and replace every source = \"../modules/...\" with the modules repo source"

check_code "the modules repo's CI runs terraform test" \
  '[[ -n "${MODULES_DIR:-}" ]] && compgen -G "$MODULES_DIR/.github/workflows/*.y*ml" >/dev/null && grep -qsE "terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+test" "$MODULES_DIR"/.github/workflows/*.y*ml' \
  "copy the starter workflow (~/.platform-lab/starter/tf-19/ci.yml) to $MODULES_DIR/.github/workflows/ci.yml"

check "$TF19_MODS is a public repo" \
  '[[ "$(gh api "repos/$TF19_MODS" --jq .visibility)" == public ]]' \
  "create it public: gh repo create $TF19_MODS --public (public, so CI clones the module without credentials)"

check "tag v1.0.0 exists in $TF19_MODS" \
  '[[ "$(gh api "repos/$TF19_MODS/git/refs/tags/v1.0.0" --jq .ref)" == refs/tags/v1.0.0 ]]' \
  "tag the release and push it: git tag -a v1.0.0 -m \"spoke v1.0.0\" && git push origin v1.0.0"

check "v1.0.0 contains the spoke module" \
  'gh api "repos/$TF19_MODS/contents/spoke?ref=v1.0.0" --jq ".[].name" | grep -c "\.tf$" >/dev/null' \
  "the tag v1.0.0 has no spoke/*.tf: tag the commit that holds the module"

check "the latest terraform run on main succeeded" \
  'ci_main_green "$TF19_LIVE"' \
  "the newest completed terraform.yml run on main in $TF19_LIVE is not green (merged? can CI reach $TF19_MODS at v1.0.0?)"
