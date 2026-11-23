# cap-01 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/web-vm.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../../ansible/lib/ansible.sh"

export CAP01_REPO="$GH_OWNER/$LIVE_REPO" CAP01_TF_WF=.github/workflows/terraform.yml

# cap01_on_block <file> <event>: the lines of on.<event> in a workflow (from "  <event>:" to the
# next key at the same or a smaller indent), comments dropped.
cap01_on_block() {
  awk -v ev="$2" '/^[[:space:]]*#/ { next }
    on && $0 ~ "^[[:space:]]+" ev ":" { ind = match($0, /[^[:space:]]/); grab = 1; print; next }
    grab && /[^[:space:]]/ { if (match($0, /[^[:space:]]/) <= ind) { grab = 0 } else { print } }
    /^on:/ { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0; grab = 0 }' "$1"
}

# cap01_wf_names (on.workflow_run lines on stdin): the workflow names it lists, one per line,
# quotes stripped: workflows: [a, "b"], workflows: a, or workflows: followed by "- a" items.
cap01_wf_names() {
  awk '/workflows:/ { w = 1; l = $0; sub(/.*workflows:[[:space:]]*/, "", l)
      if (l ~ /^\[/) { gsub(/[][]/, "", l); n = split(l, a, ","); for (i = 1; i <= n; i++) print a[i]; w = 0 }
      else if (l ~ /[^[:space:]]/) { print l; w = 0 }
      next }
    w && /^[[:space:]]*-[[:space:]]/ { l = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", l); print l; next }
    w { w = 0 }' | sed -E "s/^[[:space:]]*[\"']?//; s/[\"']?[[:space:]]*(#.*)?$//"
}

# cap01_trigger: ansible.yml starts when the Terraform pipeline finishes: on.workflow_run names
# terraform.yml's workflow (by its name:), types completed, branches main; or on.repository_dispatch,
# with terraform.yml sending one (the REST dispatches endpoint or an action that calls it).
cap01_trigger() {
  local wr name
  [[ -f "$AN_WF" ]] || return 1
  wr="$(cap01_on_block "$AN_WF" workflow_run)"
  if [[ -n "$wr" ]]; then
    name="$(sed -nE 's/^name:[[:space:]]*["'"'"']?([^"'"'"'#]*[^"'"'"'#[:space:]]).*$/\1/p' "$CAP01_TF_WF" | head -n1)"
    cap01_wf_names <<<"$wr" | grep -qxF -- "${name:-terraform}" && grep -qE "completed" <<<"$wr" && grep -qE "main" <<<"$wr" && return 0
    echo "on.workflow_run must name the workflow \"${name:-terraform}\" (terraform.yml's name:), types: [completed], branches: [main]"
    return 1
  fi
  [[ -n "$(cap01_on_block "$AN_WF" repository_dispatch)" ]] &&
    grep -vE "^[[:space:]]*#" "$CAP01_TF_WF" | grep -qE "/dispatches|repository-dispatch"
}

# cap01_apply_guard: job apply runs for that trigger only when it should. workflow_run: the
# Terraform run succeeded, wasn't a pull request's run and ran in this repo (a fork's branch can
# be called main too). repository_dispatch: the job's if: names the event.
cap01_apply_guard() {
  local body
  body="$(an_wf_job apply)" || return 1
  if [[ -n "$(cap01_on_block "$AN_WF" workflow_run)" ]]; then
    grep -qE "github\.event_name[[:space:]]*==[[:space:]]*.workflow_run." <<<"$body" || { echo "apply's if: doesn't run for workflow_run"; return 1; }
    grep -qE "workflow_run\.conclusion[[:space:]]*==[[:space:]]*.success." <<<"$body" || { echo "apply runs after failed Terraform runs (github.event.workflow_run.conclusion == 'success')"; return 1; }
    grep -qE "workflow_run\.event[[:space:]]*!=[[:space:]]*.pull_request.|workflow_run\.event[[:space:]]*==[[:space:]]*.(push|workflow_dispatch)." <<<"$body" ||
      { echo "apply runs after pull request runs (github.event.workflow_run.event != 'pull_request')"; return 1; }
    grep -qE "workflow_run\.head_repository\.full_name[[:space:]]*==[[:space:]]*github\.repository|github\.repository[[:space:]]*==[[:space:]]*github\.event\.workflow_run\.head_repository\.full_name" <<<"$body" ||
      { echo "apply runs for forks' runs (github.event.workflow_run.head_repository.full_name == github.repository)"; return 1; }
    return 0
  fi
  grep -qE "repository_dispatch" <<<"$body"
}

# cap01_tf_runner_key: terraform.yml hands the repo variable RUNNER_SSH_PUBLIC_KEY to Terraform
# (TF_VAR_<name>), env-dev declares variable "<name>" and uses var.<name>.
cap01_tf_runner_key() {
  local v
  v="$(sed -nE 's/^[[:space:]]*TF_VAR_([A-Za-z0-9_]+):[[:space:]]*\$\{\{[[:space:]]*vars\.RUNNER_SSH_PUBLIC_KEY[[:space:]]*\}\}.*$/\1/p' "$CAP01_TF_WF" 2>/dev/null | head -n1)"
  [[ -n "$v" ]] || { echo "no TF_VAR_<name>: \${{ vars.RUNNER_SSH_PUBLIC_KEY }} in $CAP01_TF_WF"; return 1; }
  grep -rqsE --include='*.tf' --exclude-dir=.terraform "variable[[:space:]]+\"$v\"" terraform/env-dev || { echo "env-dev declares no variable \"$v\""; return 1; }
  grep -rqsE --include='*.tf' --exclude-dir=.terraform "var\.$v([^A-Za-z0-9_]|$)" terraform/env-dev || { echo "env-dev never uses var.$v"; return 1; }
}

# cap01_module_release: the modules repo's linux-vm takes extra_ssh_public_keys for the admin user
# (a dynamic admin_ssh_key block), ignores later key changes (lifecycle ignore_changes on
# admin_ssh_key), CHANGELOG.md has 3.2.0, and env-dev's web VMs pin linux-vm at v3.2.0.
cap01_module_release() {
  local m="${MODULES_DIR:?}/linux-vm"
  grep -rqsE --include='*.tf' "variable[[:space:]]+\"extra_ssh_public_keys\"" "$m" || { echo "linux-vm has no variable extra_ssh_public_keys"; return 1; }
  if ! grep -rqsE --include='*.tf' "dynamic[[:space:]]+\"admin_ssh_key\"" "$m" || ! grep -rqsE --include='*.tf' "var\.extra_ssh_public_keys" "$m"; then
    echo "linux-vm doesn't turn extra_ssh_public_keys into admin_ssh_key blocks"
    return 1
  fi
  grep -rqsE --include='*.tf' "ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*admin_ssh_key" "$m" || { echo "linux-vm would replace running VMs on a key change (lifecycle ignore_changes = [admin_ssh_key])"; return 1; }
  grep -qsE "^##[[:space:]]*\[?v?3\.2\.0" "$MODULES_DIR/CHANGELOG.md" || { echo "no 3.2.0 entry in CHANGELOG.md"; return 1; }
  grep -rqsE --include='*.tf' --exclude-dir=.terraform "//linux-vm\?ref=v3\.2\.0\"" terraform/env-dev || { echo "env-dev doesn't pin linux-vm?ref=v3.2.0"; return 1; }
}

# cap01_first_contact: CI's login user is a template (ci/runner.yml or the file the runner jobs
# pass with -e @...), and site.yml or a playbook it imports tries hosts with ignore_unreachable
# and switches the login for those that are unreachable.
cap01_first_contact() {
  local f ok=0
  grep -rqsE "^ansible_user:[[:space:]]*.?\{\{" ansible/ci || { echo "ansible/ci/runner.yml: ansible_user is a fixed value (a template with a default of ops lets a play switch it)"; return 1; }
  for f in site.yml $(sed -nE 's/^[[:space:]]*(ansible\.builtin\.)?import_playbook:[[:space:]]*["'"'"']?(\.\/)?([^"'"'"'[:space:]]+).*$/\3/p' ansible/site.yml 2>/dev/null); do
    grep -qsE "ignore_unreachable:[[:space:]]*.?(true|yes)" "ansible/$f" && grep -qsE "is[[:space:]]+(ansible\.builtin\.)?unreachable" "ansible/$f" && ok=1
  done
  [[ $ok -eq 1 ]] || { echo "no play in site.yml (or a playbook it imports) tries the hosts with ignore_unreachable: true and acts on is unreachable"; return 1; }
}

# cap01_vm_new: the VM exists, runs, and is not the VM setup.sh deleted (another vmId).
cap01_vm_new() {
  local id old
  id="$(az vm show -g "$(cap01_rg)" -n "$(cap01_vm)" -d --query "[vmId, powerState]" -o tsv)" || return 1
  [[ "$id" == *"VM running"* ]] || { echo "not running: $id"; return 1; }
  old="$(cap01_snap_get vm_id)"
  [[ -z "$old" || "$id" != "$old"* ]]
}

# cap01_var_is_runner_key: RUNNER_SSH_PUBLIC_KEY is gh-runner's current public key on the jump
# host (after a pause/resume the jump host's runner has a new key; runner-register.sh updates it).
cap01_var_is_runner_key() {
  local v k
  v="$(cap01_repo_var RUNNER_SSH_PUBLIC_KEY)"
  [[ -n "$v" ]] || { echo "no repo variable RUNNER_SSH_PUBLIC_KEY"; return 1; }
  k="$(cap01_runner_pubkey)" || { echo "cannot read gh-runner's key on the jump host"; return 1; }
  [[ "$(cap01_key_body "$v")" == "$(cap01_key_body "$k")" ]]
}

# cap01_vm_runner_login: the rebuilt VM authorizes a key for azureuser besides your lab key
# (SSH_PUBLIC_KEY): the runner's, from when the VM was built.
cap01_vm_runner_login() {
  local lab k n=0
  lab="$(cap01_key_body "$(cap01_repo_var SSH_PUBLIC_KEY)")"
  while IFS= read -r k; do
    [[ -n "$k" && "$(cap01_key_body "$k")" != "$lab" ]] && n=$((n + 1))
  done < <(cap01_vm_keys)
  [[ $n -ge 1 ]]
}

# cap01_triggered_run: the newest completed ansible.yml run started by workflow_run or
# repository_dispatch was created after the VM, succeeded, and its apply job succeeded.
cap01_triggered_run() {
  local created run
  created="$(az vm show -g "$(cap01_rg)" -n "$(cap01_vm)" --query timeCreated -o tsv)" || return 1
  [[ -n "$created" ]] || return 1
  run="$(gh api "repos/$CAP01_REPO/actions/workflows/ansible.yml/runs?status=completed&per_page=50" \
    --jq '[.workflow_runs[] | select(.event == "workflow_run" or .event == "repository_dispatch")][0] // {} | {id, conclusion, created_at, event}')" || return 1
  jq -e --arg c "$created" '.id != null and .conclusion == "success" and
    (.created_at | fromdateiso8601) >= ($c | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601)' <<<"$run" >/dev/null ||
    { echo "newest triggered run: $run (VM created $created)"; return 1; }
  an_wf_run_jobs "$CAP01_REPO" "$(jq -r .id <<<"$run")" | jq -se 'any(.[]; .name == "apply" and .conclusion == "success")' >/dev/null
}

# cap01_grade_all_log: where cap01_no_regressions keeps the output of its grade --all.
cap01_grade_all_log() { printf '%s/logs/cap-01-grade-all.log\n' "${LAB_HOME:?}"; }

# cap01_no_regressions: ./lab.sh grade --all across every track, cap-01 itself excluded so it can't
# recurse. Inside a grade --all (LAB_GRADE_ALL=1) the enclosing run already grades everything.
# It takes an hour or two, so only once every other cap-01 check has passed (the results so far
# are in $GRADE_RESULTS, one P or F per check). Its output goes to cap01_grade_all_log: the
# grader shows none of a check's output, and the log's last lines name the regressions.
cap01_no_regressions() {
  local log
  [[ "${LAB_GRADE_ALL:-}" == 1 ]] && return 0
  if [[ ! -s "${GRADE_RESULTS:-}" ]] || grep -qx F "$GRADE_RESULTS"; then
    return 1
  fi
  log="$(cap01_grade_all_log)"
  mkdir -p "$(dirname "$log")"
  "${LAB_ROOT:?}/lab.sh" grade --all --exclude cap-01 >"$log" 2>&1
}
export -f cap01_on_block cap01_wf_names cap01_trigger cap01_apply_guard cap01_tf_runner_key cap01_module_release \
  cap01_first_contact cap01_vm_new cap01_var_is_runner_key cap01_vm_runner_login cap01_triggered_run \
  cap01_no_regressions cap01_grade_all_log cap01_rg cap01_vm cap01_snap cap01_snap_get cap01_vm_keys cap01_key_body \
  cap01_runner_pubkey cap01_repo_var

check_code "ansible.yml starts when the Terraform pipeline finishes on main (workflow_run or repository_dispatch)" \
  'cap01_trigger' \
  "add on: workflow_run: {workflows: [terraform], types: [completed], branches: [main]} to .github/workflows/ansible.yml (or on: repository_dispatch, sent by terraform.yml's apply job)"

check_code "job apply runs after a successful, non-PR Terraform run of this repo, and keeps the fork guard" \
  'cap01_apply_guard && an_wf_fork_guard apply' \
  "extend apply's if: with || (github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event != 'pull_request' && github.event.workflow_run.head_repository.full_name == github.repository), keeping the fork guard"

check_code "terraform.yml passes RUNNER_SSH_PUBLIC_KEY to env-dev, which authorizes it for the web VMs" \
  'cap01_tf_runner_key' \
  "add TF_VAR_runner_ssh_public_key: \${{ vars.RUNNER_SSH_PUBLIC_KEY }} to terraform.yml's env, a variable runner_ssh_public_key (default \"\") to terraform/env-dev, and pass it to module \"web\" (extra_ssh_public_keys = compact([var.runner_ssh_public_key]))"

check_code "linux-vm v3.2.0: extra_ssh_public_keys, key changes don't replace running VMs; env-dev pins v3.2.0" \
  'cap01_module_release' \
  "in $MODULES_REPO: variable extra_ssh_public_keys, a dynamic \"admin_ssh_key\" block over it, lifecycle { ignore_changes = [admin_ssh_key] }, a 3.2.0 entry in CHANGELOG.md, tag v3.2.0; then linux-vm?ref=v3.2.0 in terraform/env-dev"

check_code "CI's first contact: a play tries every host and logs in as azureuser where ops doesn't exist yet" \
  'cap01_first_contact' \
  "ci/runner.yml: ansible_user: \"{{ acme_ci_login | default('ops') }}\"; a play imported by site.yml after the guard pings with ignore_unreachable: true and sets acme_ci_login: azureuser when the result is unreachable"

check "vm-$PREFIX-web-dev-2 is back: running, and a new VM (not the one the incident deleted)" \
  'cap01_vm_new' \
  "vm-$PREFIX-web-dev-2 must exist in rg-$PREFIX-dev and run, rebuilt by the Terraform pipeline (merge your change, or gh workflow run terraform.yml -f stacks=env-dev)"

# From here on the checks load the inventory or SSH through the jump host: 180 s, as an-* do.
cap01_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "repo variable RUNNER_SSH_PUBLIC_KEY holds gh-runner's public key from the jump host" \
  'cap01_var_is_runner_key' \
  "set it from the jump host: ssh to vm-$PREFIX-jump, sudo cat /home/gh-runner/.ssh/id_ed25519.pub, then gh variable set RUNNER_SSH_PUBLIC_KEY -R $CAP01_REPO (the public half only)"

check "vm-$PREFIX-web-dev-2 lets the runner's key log in as azureuser" \
  'cap01_vm_runner_login' \
  "az vm show -g rg-$PREFIX-dev -n vm-$PREFIX-web-dev-2 --query osProfile.linuxConfiguration.ssh.publicKeys must list a key besides SSH_PUBLIC_KEY: set RUNNER_SSH_PUBLIC_KEY before the pipeline builds the VM"

check "the newest ansible.yml run started by the Terraform pipeline (workflow_run/repository_dispatch) came after the VM and applied green" \
  'cap01_triggered_run' \
  "the Terraform run that rebuilt vm-$PREFIX-web-dev-2 must trigger ansible.yml by itself, and its apply job must succeed on the new VM (no gh workflow run ansible.yml, no ansible-playbook from your machine)"

check "HAProxy on the jump host sends requests to both vm-$PREFIX-web-dev-1 and vm-$PREFIX-web-dev-2" \
  'an_probe role_jump 1 haproxy.sh "vm-$PREFIX-web-dev-1" "vm-$PREFIX-web-dev-2"' \
  "on the jump host, for i in \$(seq 10); do curl -s localhost; done must show both web VMs (the triggered run configures the new VM and HAProxy)"

# Last and slow: every finished task of every track again (Molecule included), and only once the
# checks above all pass.
GRADE_TIMEOUT=10800
check "./lab.sh grade --all: no regressions in any track (runs only when every check above passes)" \
  'cap01_no_regressions' \
  "not run while a check above fails (fix those first); if they all passed, ./lab.sh grade --all found regressions: the end of $(cap01_grade_all_log) names them"
GRADE_TIMEOUT="$cap01_timeout"
