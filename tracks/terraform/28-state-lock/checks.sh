# tf-28 checks (sourced by the grader; cwd = LIVE_DIR)
# no check_code: the incident and its fix are state, not code (a lease on a blob, a CI run); the
# repo doesn't change.

export TF28_SA="st${PREFIX}tfstate$SUFFIX" TF28_REPO="$GH_OWNER/$LIVE_REPO"
export TF28_SNAP="$LAB_HOME/snapshots/tf-28.lock"

# tf28_blob <az storage blob subcommand...>: runs it against env-dev.tfstate.
tf28_blob() {
  local sub=$1
  shift
  az storage blob "$sub" --auth-mode login --account-name "$TF28_SA" --container-name tfstate --name env-dev.tfstate "$@"
}
# tf28_lock_gone: the incident's lock ID is no longer in the blob's terraformlockid metadata.
tf28_lock_gone() {
  local id held
  [[ -s "$TF28_SNAP" ]] || return 0
  id="$(head -n1 "$TF28_SNAP")"
  held="$(tf28_blob metadata show -o json | jq -r '.terraformlockid // empty' | base64 -d 2>/dev/null | jq -r '.ID // empty' || true)"
  [[ "$held" != "$id" ]]
}
# tf28_green_since: a terraform.yml run created after the incident (or ever, without a snapshot)
# completed successfully.
tf28_green_since() {
  local since=0 iso
  [[ -s "$TF28_SNAP" ]] && since="$(sed -n 2p "$TF28_SNAP")"
  iso="$(date -u -d "@$since" +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$(gh api "repos/$TF28_REPO/actions/workflows/terraform.yml/runs?status=success&created=%3E%3D$iso&per_page=1" --jq .total_count)" -ge 1 ]]
}
export -f tf28_blob tf28_lock_gone tf28_green_since

check "the lease on env-dev.tfstate is no longer held" \
  '[[ "$(tf28_blob show --query properties.lease.state -o tsv)" =~ ^(available|broken|expired)$ ]]' \
  "env-dev.tfstate in $TF28_SA is still leased: terraform force-unlock <ID> in terraform/env-dev"

check "the stale lock is gone from the state blob" \
  'tf28_lock_gone' \
  "the lock info of the incident is still in env-dev.tfstate's metadata (terraformlockid): terraform force-unlock <ID>"

check "a terraform.yml run that started after the incident is green" \
  'tf28_green_since' \
  "no successful terraform.yml run since the lock appeared: gh workflow run terraform.yml -f stacks=env-dev"
