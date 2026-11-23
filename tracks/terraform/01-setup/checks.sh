# tf-01 checks (sourced by the grader; cwd = LIVE_DIR)

check "terraform 1.17 or newer (Linux build) is on PATH" \
  'p="$(type -P terraform)" && [[ "$p" != /mnt/* ]] && v="$(terraform version -json | jq -r .terraform_version)" && [[ "$(printf "%s\n" 1.17.0 "$v" | sort -V | head -n 1)" == 1.17.0 ]]' \
  "need the Linux terraform >= 1.17 first on PATH (type -a terraform)"

check "Linux az is logged in to the lab subscription" \
  'p="$(type -P az)" && [[ "$p" != /mnt/* ]] && [[ "$(az account show --query id -o tsv)" == "$SUBSCRIPTION_ID" ]]' \
  "az must be the Linux build and az account show must be on $SUBSCRIPTION_ID"

check "GitHub repo $GH_OWNER/$LIVE_REPO exists and is public" \
  '[[ "$(gh api "repos/$GH_OWNER/$LIVE_REPO" --jq .visibility)" == public ]]' \
  "gh api repos/$GH_OWNER/$LIVE_REPO must show visibility public"

check "LIVE_DIR is a clone of $GH_OWNER/$LIVE_REPO" \
  'git remote get-url origin | grep -Eiq "[:/]$GH_OWNER/$LIVE_REPO(\.git)?$"' \
  "$LIVE_DIR must be a git clone whose origin is $GH_OWNER/$LIVE_REPO"

check ".gitignore is pushed to main on GitHub" \
  '[[ "$(gh api "repos/$GH_OWNER/$LIVE_REPO/contents/.gitignore?ref=main" --jq .name)" == .gitignore ]]' \
  "no .gitignore on main in $GH_OWNER/$LIVE_REPO; commit and push it"

# Patterns are tested in a scratch repo so the check works whatever the learner's tree holds.
check_code ".gitignore ignores .terraform/, state files and *.tfvars" \
  '[[ -f .gitignore ]] && t="$(mktemp -d)" && trap "rm -rf \"$t\"" EXIT && cp .gitignore "$t/" && git -C "$t" init -q && for p in .terraform/x terraform/bootstrap/.terraform/providers/x terraform.tfstate terraform/bootstrap/terraform.tfstate terraform/bootstrap/terraform.tfstate.backup terraform/bootstrap/terraform.tfstate.1700000000.backup terraform/env-dev/secret.tfvars terraform/env-dev/dev.auto.tfvars; do git -C "$t" check-ignore -q --no-index "$p" || exit 1; done' \
  "root .gitignore must ignore .terraform/ (any depth), *.tfstate, *.tfstate.* and *.tfvars"

check_code ".gitignore keeps *.auto.tfvars.example and .terraform.lock.hcl" \
  '[[ -f .gitignore ]] && t="$(mktemp -d)" && trap "rm -rf \"$t\"" EXIT && cp .gitignore "$t/" && git -C "$t" init -q && for p in terraform/env-dev/dev.auto.tfvars.example terraform/bootstrap/.terraform.lock.hcl; do ! git -C "$t" check-ignore -q --no-index "$p" || exit 1; done' \
  ".gitignore must not ignore *.auto.tfvars.example or .terraform.lock.hcl"
