# an-11 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an11_rolling_code: a playbook updates one server at a time (serial), stops at the first failure
# (max_fail_percentage: 0 or any_errors_fatal), and talks to HAProxy on the jump host by
# delegation.
an11_rolling_code() {
  local f
  while IFS= read -r f; do
    grep -qE "^[[:space:]]*serial:[[:space:]]*[^[:space:]]" "$f" || continue
    grep -qE "^[[:space:]]*(max_fail_percentage:[[:space:]]*.?0.?|any_errors_fatal:[[:space:]]*.?true.?)[[:space:]]*(#.*)?$" "$f" || continue
    an_delegates_to "$f" role_jump && return 0
  done < <(an_playbooks)
  return 1
}

# an11_rolling_under_load: on the jump host a loop requests http://127.0.0.1/ every 0.2 s (probe
# rolling-load.sh, detached, ends by itself after AN11_SECS). Meanwhile the learner's rolling.yml
# runs twice: a one-off back to 1.0.0, then a plain run (the inventory's 1.1.0). Every request
# must have answered 200. The loop is stopped on the way out, also when this check fails or is
# interrupted; if even that is cut short, its own timeout ends it.
AN11_SECS=960
an11_rolling_under_load() {
  local rc=0 out stop
  [[ "$(an_count role_jump)" -ge 1 && "$(an_count role_web)" -ge 2 ]] || return 1
  stop="an_run ansible role_jump -b -m ansible.builtin.script -a '$AN_PROBES/rolling-load.sh stop an-11'"
  an_run ansible role_jump -b -m ansible.builtin.script -a "$AN_PROBES/rolling-load.sh start an-11 $AN11_SECS" >/dev/null || return 1
  # shellcheck disable=SC2064 # the command is fixed now, on purpose
  trap "$stop >/dev/null 2>&1 || true" EXIT INT TERM
  an_run ansible-playbook rolling.yml -e app_version=1.0.0 >/dev/null 2>&1 || { echo "rolling.yml -e app_version=1.0.0 failed"; rc=1; }
  if [[ $rc -eq 0 ]]; then
    an_run ansible-playbook rolling.yml >/dev/null 2>&1 || { echo "rolling.yml failed"; rc=1; }
  fi
  trap - EXIT INT TERM
  out="$(eval "$stop" 2>&1)" || rc=1
  grep -oE "(answers other than 200: [^\"]*|requests: [0-9]+, failed: [0-9]+)" <<<"$out" | sort -u
  return "$rc"
}
export AN11_SECS
export -f an11_rolling_code an11_rolling_under_load

check_code "a rolling playbook: serial, stop at the first failure, HAProxy drained and enabled by delegation to role_jump" \
  'an11_rolling_code' \
  "write ansible/rolling.yml: a play for role_web with serial: 1 and max_fail_percentage: 0, pre_tasks that drain the server in HAProxy and post_tasks that enable it, each with delegate_to: \"{{ groups['role_jump'] | first }}\" (the load balancer from the inventory, never a name or IP)"

check_code "the inventory deploys release 1.1.0 (app_version in the web servers' group variables)" \
  'grep -rqsE "^app_version:[[:space:]]*[\"'"'"']?1\.1\.0[\"'"'"']?[[:space:]]*(#.*)?$" ansible/inventory/group_vars/role_web.yml ansible/inventory/group_vars/role_web' \
  "set app_version: \"1.1.0\" in ansible/inventory/group_vars/role_web.yml: the release is a reviewed change to that line, -e app_version is for one-offs"

# Two rolling runs over two servers with health gates, inventory loads included: up to 15 minutes.
an11_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=900
check "under a request every 0.2 s through HAProxy, rolling.yml -e app_version=1.0.0 and then rolling.yml drop no request" \
  'an11_rolling_under_load' \
  "on the jump host, every request to http://127.0.0.1/ during both rolling runs must answer 200: drain a server before it changes, wait for its /health, and wait until HAProxy reports it UP before the next one leaves the pool (cd ansible && ansible-playbook rolling.yml must also succeed on its own)"

GRADE_TIMEOUT=180
check "both web VMs: acme-hello healthy with /health = ok 1.1.0" \
  'an_probe role_web 2 app-health.sh 1.1.0' \
  "curl -s localhost/health on each web VM must print ok 1.1.0 after a plain rolling.yml run"

# Runs the learner's site.yml once more: it must agree with rolling.yml (documented probe).
GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml must report changed=0 for every VM after the rolling update: both playbooks deploy the release in the inventory"
GRADE_TIMEOUT="$an11_timeout"
