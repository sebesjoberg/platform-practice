# an-18 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN18_PB=ansible/deploy.yml

# an18_structure: deploy.yml updates one server at a time and stops at the first failure, with a
# block/rescue/always around the deploy: the rescue runs role acme_hello again (or switches
# current back) and then fails the run, the always gives the server back to HAProxy by delegation
# to role_jump.
an18_structure() {
  local f=$AN18_PB rescue always
  [[ -f "$f" ]] || { echo "no $f"; return 1; }
  grep -qE "^[[:space:]]*serial:[[:space:]]*[^[:space:]]" "$f" || { echo "no serial"; return 1; }
  grep -qE "^[[:space:]]*(max_fail_percentage:[[:space:]]*.?0.?|any_errors_fatal:[[:space:]]*.?true.?)[[:space:]]*(#.*)?$" "$f" || { echo "no max_fail_percentage: 0"; return 1; }
  { grep -qE "^[[:space:]]*(-[[:space:]]+)?block:" "$f" && grep -qE "^[[:space:]]*rescue:" "$f" && grep -qE "^[[:space:]]*always:" "$f"; } ||
    { echo "no block/rescue/always"; return 1; }
  rescue="$(sed -n '/^[[:space:]]*rescue:/,/^[[:space:]]*always:/p' "$f")"
  always="$(sed -n '/^[[:space:]]*always:/,$p' "$f")"
  grep -qE "acme_hello|current" <<<"$rescue" || { echo "the rescue doesn't roll the app back"; return 1; }
  grep -qE "(ansible\.builtin\.)?fail:" <<<"$rescue" || { echo "the rescue doesn't fail the run"; return 1; }
  grep -qE "state:[[:space:]]*.?(enabled|ready)|enable server|state ready" <<<"$always" ||
    { echo "the always section doesn't put the server back into HAProxy"; return 1; }
  an_delegates_to "$f" role_jump || { echo "HAProxy steps are not delegated to role_jump"; return 1; }
}

# an18_remembers_previous: deploy.yml finds the release that runs now before it deploys.
an18_remembers_previous() {
  grep -qE "lnk_target|readlink|realpath|/current" "$AN18_PB"
}

# an18_broken_rolls_back: deploy.yml -e app_version=broken must fail; afterwards both web VMs
# answer /health with the inventory's release and HAProxy reaches both again.
an18_broken_rolls_back() {
  local v
  v="$(an_hostvar "vm-$PREFIX-web-dev-1" app_version)"
  [[ -n "$v" && "$v" != broken ]] || return 1
  if an_run ansible-playbook deploy.yml -e app_version=broken >/dev/null 2>&1; then
    echo "deploy.yml -e app_version=broken exited 0"
    return 1
  fi
  an_probe role_web 2 app-health.sh "$v" >/dev/null || { echo "a web VM doesn't serve ok $v after the failed deploy"; return 1; }
  an_probe role_jump 1 haproxy.sh "vm-$PREFIX-web-dev-1" "vm-$PREFIX-web-dev-2" >/dev/null ||
    { echo "HAProxy doesn't reach both web VMs after the failed deploy"; return 1; }
}
export -f an18_structure an18_remembers_previous an18_broken_rolls_back

check_code "deploy.yml: serial, stop at the first failure, block/rescue/always (rescue rolls back and fails, always rejoins HAProxy via role_jump)" \
  'an18_structure' \
  "write ansible/deploy.yml: serial: 1, max_fail_percentage: 0; a block that drains the server and deploys acme.platform.acme_hello, a rescue that switches back to the previous release and then fails, an always that enables the server in HAProxy (delegate_to the role_jump host)"

check_code "deploy.yml remembers the release that ran before (the current symlink)" \
  'an18_remembers_previous' \
  "before deploying, read /opt/acme-hello/current (stat: lnk_target) so the rescue knows what to switch back to"

an18_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=600
check "deploy.yml -e app_version=broken fails, both web VMs still serve the inventory's release, HAProxy reaches both" \
  'an18_broken_rolls_back' \
  "cd ansible && ansible-playbook deploy.yml -e app_version=broken must exit non-zero, and afterwards curl -s localhost/health on both web VMs prints the inventory's release and HAProxy has both servers UP"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml after the failed deploy must report changed=0: the rollback restored exactly the inventory's state"
GRADE_TIMEOUT="$an18_timeout"
