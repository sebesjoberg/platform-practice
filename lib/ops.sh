# shellcheck shell=bash
# Cost control: pause, resume, nuke, cost.

# observability (tf-29) holds the Log Analytics workspace that used to live in landing-zone. It
# costs next to nothing (0.1 GB daily cap) and keeps the platform's logs and workspace ID, so pause
# leaves it running, like landing-zone. nuke destroys it.
PAUSE_ORDER=(teams/payments env-prod env-dev shared)
NUKE_ORDER=(teams/payments observability env-prod env-dev shared landing-zone)

# tf_stack <stack> <verb...>: run init then the verb against one stack dir; dies naming the stack on failure.
tf_stack() {
  local stack=$1 dir
  shift
  dir="$LIVE_DIR/terraform/$stack"
  terraform -chdir="$dir" init -input=false </dev/null || die 1 "terraform init failed for $stack"
  terraform -chdir="$dir" "$@" </dev/null || die 1 "terraform $1 failed for $stack"
}

# Placeholder SSH key for destroys without ~/.ssh/<prefix>_lab.pub: a real ed25519 public key
# (the provider parses it) whose private half was deleted. Nothing ever logs in with it.
LAB_PLACEHOLDER_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbG5bSUW5X3XwP7w2zy2uRxzooFWF1cNkhrNJ3menoy lab-destroy-placeholder"

# lab_destroy_vars: values for the stack variables without defaults, which CI sets from repo
# variables (TF_VAR_*). A local destroy needs every variable but never sends these anywhere:
# landing-zone's budget_email (tf-12), shared's learner_ip and shared/env-dev's ssh_public_key
# (tf-25). Values already in the environment win.
lab_destroy_vars() {
  export TF_VAR_budget_email="${TF_VAR_budget_email:-nuke@example.invalid}"
  export TF_VAR_learner_ip="${TF_VAR_learner_ip:-${LEARNER_IP:-192.0.2.1}}"
  if [[ -z "${TF_VAR_ssh_public_key:-}" ]]; then
    if [[ -f "$HOME/.ssh/${PREFIX}_lab.pub" ]]; then
      TF_VAR_ssh_public_key="$(cat "$HOME/.ssh/${PREFIX}_lab.pub")"
    else
      TF_VAR_ssh_public_key="$LAB_PLACEHOLDER_SSH_KEY"
    fi
    export TF_VAR_ssh_public_key
  fi
}

# resume_import_image: from tf-23 env-dev runs hello:1.0 from the shared registry, which pause
# destroyed. Terraform doesn't push images: apply shared first, import the image once the
# registry exists (tracks/terraform/lib/acr-image.sh, as tf-22 does), and only then dispatch the
# full run, which queues behind the shared one.
resume_import_image() {
  local lib="$TRACKS_DIR/terraform/lib/acr-image.sh"
  [[ -f "$lib" && -d "$LIVE_DIR/terraform/shared" ]] || return 0
  # shellcheck source=/dev/null
  source "$lib"
  acr_hello_needed "$LIVE_DIR" || return 0
  need az
  echo "resume: applying shared first, to import the app image into the new registry"
  gh workflow run terraform.yml --ref main -f stacks=shared </dev/null || die 1 "could not dispatch terraform.yml"
  acr_wait_ready "${RESUME_ACR_WAIT:-1200}" </dev/null || die 1 "the registry did not come back; see gh run list --workflow terraform.yml"
  acr_hello_import </dev/null || die 1 "could not import the app image into $(acr_name)"
}

# drift_workflow <enable|disable>: from tf-27 the live repo has a scheduled drift.yml. While the
# lab is paused every destroyed stack plans as "create everything", so pause disables it and
# resume enables it again. Best effort: a failure only prints a warning.
drift_workflow() {
  [[ -f "$LIVE_DIR/.github/workflows/drift.yml" ]] || return 0
  need gh
  gh workflow "$1" drift.yml -R "$GH_OWNER/$LIVE_REPO" </dev/null >/dev/null ||
    echo "warning: could not $1 drift.yml in $GH_OWNER/$LIVE_REPO (gh workflow $1 drift.yml)" >&2
}

cmd_pause() {
  load_config
  need terraform
  lab_destroy_vars
  drift_workflow disable
  local stack
  for stack in "${PAUSE_ORDER[@]}"; do
    [[ -d "$LIVE_DIR/terraform/$stack" ]] || continue
    echo "pause: destroying $stack"
    tf_stack "$stack" destroy -auto-approve -input=false
  done
  mkdir -p "$LAB_HOME"
  : >"$LAB_HOME/paused"
  echo "paused; ./lab.sh resume brings it back"
}

any_ansible_done() {
  [[ -f "$(progress_file)" ]] || return 1
  awk -F'\t' '$1 ~ /^an-/ && $3 != "" {found=1} END {exit !found}' "$(progress_file)"
}

cmd_resume() {
  load_config
  local i stack
  if [[ -f "$LIVE_DIR/.github/workflows/terraform.yml" ]]; then
    need gh
    resume_import_image
    gh workflow run terraform.yml --ref main -f stacks=all </dev/null || die 1 "could not dispatch terraform.yml"
    if [[ -f "$LIVE_DIR/terraform/env-prod/main.tf" ]] && grep -qs 'environment:[[:space:]]*prod' "$LIVE_DIR/.github/workflows/terraform.yml"; then
      echo "resume: approve the run's apply-prod job (Actions tab, Review deployments) to rebuild prod"
    fi
  else
    need terraform
    for ((i = ${#PAUSE_ORDER[@]} - 1; i >= 0; i--)); do
      stack=${PAUSE_ORDER[i]}
      [[ -d "$LIVE_DIR/terraform/$stack" ]] || continue
      echo "resume: applying $stack"
      tf_stack "$stack" apply -auto-approve -input=false
    done
  fi
  if progress_done an-16; then
    need gh
    gh workflow run ansible.yml --ref main -f env=dev </dev/null || die 1 "could not dispatch ansible.yml"
  elif any_ansible_done; then
    need ansible-playbook
    (cd "$LIVE_DIR/ansible" && ansible-playbook -i inventory site.yml </dev/null) || die 1 "ansible-playbook failed"
  fi
  drift_workflow enable
  rm -f "$LAB_HOME/paused"
  echo "resumed"
}

# confirm_typed <expected> <prompt>: reads one line from stdin; exit 6 on mismatch.
confirm_typed() {
  local reply=""
  printf '%s ' "$2"
  read -r reply || true
  [[ "$reply" == "$1" ]] || die 6 "nuke: confirmation did not match; nothing was done"
}

cmd_nuke() {
  load_config
  need az gh terraform
  confirm_typed "$PREFIX" "Type the prefix ($PREFIX) to confirm:"
  confirm_typed nuke "Type 'nuke' to destroy everything:"

  local stack pid rg="rg-$PREFIX-tfstate" active
  active="$(az account show --query id -o tsv </dev/null 2>/dev/null | tr -d '\r')" || active=""
  [[ "$active" == "${SUBSCRIPTION_ID:-}" ]] ||
    die 4 "az is on subscription ${active:-<none>}, lab is $SUBSCRIPTION_ID — az account set -s $SUBSCRIPTION_ID"

  # landing-zone requires var.budget_email from tf-12 on, shared and env-dev learner_ip and
  # ssh_public_key from tf-25 (CI sets them from repo secrets and variables). Destroy never sends them
  # anywhere, so any valid value will do.
  lab_destroy_vars
  for stack in "${NUKE_ORDER[@]}"; do
    [[ -d "$LIVE_DIR/terraform/$stack" ]] || continue
    echo "nuke: destroying $stack"
    tf_stack "$stack" destroy -auto-approve -input=false
  done
  # tf-26's click-ops group, if it was never imported into landing-zone (destroyed above if it was).
  if [[ -s "$LAB_HOME/snapshots/tf-26.ids" && "$(az group exists -n "rg-$PREFIX-legacy" -o tsv </dev/null 2>/dev/null | tr -d '\r')" == true ]]; then
    az group delete -n "rg-$PREFIX-legacy" --yes </dev/null || die 1 "could not delete rg-$PREFIX-legacy"
  fi
  # tf-31: bootstrap vends each team's resource group (the stack in terraform/teams/<team> only
  # works inside it), and nuke never destroys bootstrap. Delete every vended group: those Azure
  # knows by bootstrap's tag vended_by=bootstrap (also before the team's stack exists), plus
  # rg-<prefix>-<team> for each terraform/teams/<team> (vended by code without the tag).
  local team groups g
  groups="$(az group list --tag vended_by=bootstrap --query "[?starts_with(name, 'rg-$PREFIX-')].name" -o tsv </dev/null 2>/dev/null | tr -d '\r')" || groups=""
  for team in "$LIVE_DIR"/terraform/teams/*/; do
    [[ -d "$team" ]] && groups+=$'\n'"rg-$PREFIX-$(basename "$team")"
  done
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    if [[ "$(az group exists -n "$g" -o tsv </dev/null 2>/dev/null | tr -d '\r')" == true ]]; then
      az group delete -n "$g" --yes </dev/null || die 1 "could not delete $g"
    fi
  done < <(sort -u <<<"$groups")

  if pid="$(az identity show -g "$rg" -n "id-$PREFIX-github-ci" --query principalId -o tsv </dev/null 2>/dev/null | tr -d '\r')" && [[ -n "$pid" ]]; then
    az role assignment delete --assignee "$pid" --yes </dev/null || die 1 "could not delete role assignments of $pid"
  fi
  # tf-21's bootstrap gave you Key Vault Secrets Officer on the subscription. It goes with the lab:
  # matched by principal (you, the signed-in user), role and exact scope, since your own code may
  # not set the reference's description. A service principal login has no signed-in user: skip.
  local me kv_ids=""
  me="$(az ad signed-in-user show --query id -o tsv </dev/null 2>/dev/null | tr -d '\r')" || me=""
  if [[ -n "$me" ]]; then
    kv_ids="$(az role assignment list --assignee "$me" --scope "/subscriptions/$SUBSCRIPTION_ID" --role "Key Vault Secrets Officer" \
      --query "[?scope=='/subscriptions/$SUBSCRIPTION_ID'].id" -o tsv </dev/null 2>/dev/null | tr -d '\r')" || kv_ids=""
  fi
  if [[ -n "$kv_ids" ]]; then
    # shellcheck disable=SC2086 # one ID per word
    az role assignment delete --ids $kv_ids --yes </dev/null || die 1 "could not delete your Key Vault Secrets Officer assignment"
  fi
  az group delete -n "$rg" --yes </dev/null || die 1 "could not delete $rg"

  local repo reply
  # tf-31 creates the payments team's repo; it goes with the lab too, after the same question.
  for repo in "$LIVE_REPO" "$MODULES_REPO" "$PREFIX-payments-app"; do
    printf 'Delete GitHub repo %s/%s? [y/N] ' "$GH_OWNER" "$repo"
    reply=""
    read -r reply || true
    if [[ "$reply" == y ]]; then
      gh repo delete "$GH_OWNER/$repo" --yes </dev/null || echo "could not delete $GH_OWNER/$repo" >&2
    fi
  done
  rm -f "$LAB_HOME/progress" "$LAB_HOME/paused"
  echo "nuked"
}

cmd_cost() {
  load_config
  need az jq
  local start end out
  start="$(date +%Y-%m-01)"
  end="$(date +%F)"
  if ! out="$(az consumption usage list --start-date "$start" --end-date "$end" -o json </dev/null 2>/dev/null)"; then
    echo "cost API not available for this subscription type; check the portal"
    return 0
  fi
  local sum cur
  sum="$(jq -r '[.[] | (.pretaxCost // 0 | tonumber)] | add // 0' <<<"$out" | tr -d '\r')"
  cur="$(jq -r '.[0].currency // "?"' <<<"$out" | tr -d '\r')"
  printf 'month to date: %.2f %s of budget 300
' "$sum" "$cur"
}
