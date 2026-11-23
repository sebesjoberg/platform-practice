# shellcheck shell=bash
# Cost control: pause, resume, nuke, cost.

PAUSE_ORDER=(teams/payments observability env-prod env-dev shared)
NUKE_ORDER=(teams/payments observability env-prod env-dev shared landing-zone)

# tf_stack <stack> <verb...>: run init then the verb against one stack dir; dies naming the stack on failure.
tf_stack() {
  local stack=$1 dir
  shift
  dir="$LIVE_DIR/terraform/$stack"
  terraform -chdir="$dir" init -input=false </dev/null || die 1 "terraform init failed for $stack"
  terraform -chdir="$dir" "$@" </dev/null || die 1 "terraform $1 failed for $stack"
}

cmd_pause() {
  load_config
  need terraform
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
    gh workflow run terraform.yml --ref main -f stacks=all </dev/null || die 1 "could not dispatch terraform.yml"
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
  active="$(az account show --query id -o tsv </dev/null 2>/dev/null | tr -d '')" || active=""
  [[ "$active" == "${SUBSCRIPTION_ID:-}" ]] ||
    die 4 "az is on subscription ${active:-<none>}, lab is $SUBSCRIPTION_ID — az account set -s $SUBSCRIPTION_ID"

  # landing-zone requires var.budget_email from tf-12 on (CI sets it from the BUDGET_EMAIL repo
  # variable). Destroy never sends it anywhere, so any valid address will do.
  export TF_VAR_budget_email="${TF_VAR_budget_email:-nuke@example.invalid}"
  for stack in "${NUKE_ORDER[@]}"; do
    [[ -d "$LIVE_DIR/terraform/$stack" ]] || continue
    echo "nuke: destroying $stack"
    tf_stack "$stack" destroy -auto-approve -input=false
  done

  if pid="$(az identity show -g "$rg" -n "id-$PREFIX-github-ci" --query principalId -o tsv </dev/null 2>/dev/null | tr -d '\r')" && [[ -n "$pid" ]]; then
    az role assignment delete --assignee "$pid" --yes </dev/null || die 1 "could not delete role assignments of $pid"
  fi
  az group delete -n "$rg" --yes </dev/null || die 1 "could not delete $rg"

  local repo reply
  for repo in "$LIVE_REPO" "$MODULES_REPO"; do
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
  sum="$(jq -r '[.[] | (.pretaxCost // 0 | tonumber)] | add // 0' <<<"$out" | tr -d '')"
  cur="$(jq -r '.[0].currency // "?"' <<<"$out" | tr -d '')"
  printf 'month to date: %.2f %s of budget 300
' "$sum" "$cur"
}
