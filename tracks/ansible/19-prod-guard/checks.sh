# an-19 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an19_guard_files: the playbooks (under ansible/) that hold an assert on confirm_prod.
an19_guard_files() {
  local f
  while IFS= read -r f; do
    grep -qE "confirm_prod" "$f" && grep -qE "(ansible\.builtin\.)?assert:" "$f" && echo "$f"
  done < <(an_playbooks)
  return 0
}

# an19_guard_wired: an assert on confirm_prod for env_prod hosts, in site.yml and deploy.yml
# themselves or in a playbook they import.
an19_guard_wired() {
  local p f ok
  local -a gs
  mapfile -t gs < <(an19_guard_files)
  [[ ${#gs[@]} -gt 0 ]] || { echo "no playbook asserts confirm_prod"; return 1; }
  grep -qE "env_prod" "${gs[@]}" || { echo "the guard doesn't look at env_prod"; return 1; }
  for p in ansible/site.yml ansible/deploy.yml; do
    ok=0
    for f in "${gs[@]}"; do
      [[ "$f" == "$p" ]] && ok=1
      grep -qsE "import_playbook:[[:space:]]*.?(\./)?$(basename "$f").?[[:space:]]*$" "$p" && ok=1
    done
    [[ $ok -eq 1 ]] || { echo "$p has no guard"; return 1; }
  done
}

# an19_env_prod: the inventory declares env_prod (static groups file or keyed group config) and
# has per-environment variables for prod (its own vault).
an19_env_prod() {
  grep -rqsE "^[[:space:]]+env_prod:" ansible/inventory --include='*.yml' --include='*.yaml' ||
    { echo "no group env_prod declared in ansible/inventory"; return 1; }
  grep -qE "^[[:space:]]*inventory[[:space:]]*=.*(groups|inventory[[:space:]]*$|inventory/[[:space:]]*$)" ansible/ansible.cfg ||
    grep -qE "^[[:space:]]*inventory[[:space:]]*=.*,.*" ansible/ansible.cfg || { echo "ansible.cfg doesn't load the file that declares env_prod"; return 1; }
  { grep -qsE "^acme_env:[[:space:]]*.?prod.?[[:space:]]*$" ansible/inventory/group_vars/env_prod.yml ansible/inventory/group_vars/env_prod/*.yml &&
    grep -rqsE "kv-$PREFIX-prod-$SUFFIX" ansible/inventory/group_vars/env_prod*; } || { echo "no group_vars/env_prod.yml with acme_env: prod and kv-$PREFIX-prod-$SUFFIX"; return 1; }
}

# an19_lb_dev_only: HAProxy's backends are role_web intersected with env_dev.
an19_lb_dev_only() {
  grep -rqsE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible \
    "groups\[.?role_web.?\][^#]*intersect\(groups\[.?env_dev.?\]\)|groups\[.?env_dev.?\][^#]*intersect\(groups\[.?role_web.?\]\)|role_web:&env_dev|env_dev:&role_web" ansible/inventory ansible/*.yml
}

# an19_ci_prod_job: a runner job with environment: prod passes confirm_prod=true and limits to
# env_prod; every other runner job that runs a playbook limits to dev (no confirm_prod).
an19_ci_prod_job() {
  local j body prod=0
  while IFS= read -r j; do
    body="$(an_wf_job "$j")"
    if grep -qE "^[[:space:]]+environment:[[:space:]]*.?prod" <<<"$body" || grep -qE "^[[:space:]]+name:[[:space:]]*.?prod.?[[:space:]]*$" <<<"$body"; then
      grep -qE "confirm_prod=true|confirm_prod:[[:space:]]*true" <<<"$body" && grep -qE -- "--limit[= ].?env_prod" <<<"$body" && prod=1
    elif grep -qE "(ansible-playbook|drift-check\.sh)" <<<"$body"; then
      ! grep -qE "confirm_prod" <<<"$body" || { echo "job $j says confirm_prod without the prod environment"; return 1; }
      grep -qE -- "--limit[= ].?[^ ]*env_dev" <<<"$body" || { echo "job $j doesn't limit to dev (--limit env_dev:env_hub)"; return 1; }
    fi
  done < <(an_wf_runner_jobs)
  [[ $prod -eq 1 ]] || { echo "no runner job with environment: prod, confirm_prod=true and --limit env_prod"; return 1; }
}

# an19_fixture <file>: a static inventory with a fake prod web server, a fake dev web server and a
# fake jump host on TEST-NET addresses (nothing answers; any connection attempt shows as
# UNREACHABLE within seconds). Names that no real host has, so no cached facts apply.
an19_fixture() {
  cat >"$1" <<'EOF'
all:
  vars:
    ansible_ssh_timeout: 3
  children:
    role_web:
      hosts:
        fixture-web-prod-1: {ansible_host: 192.0.2.10}
        fixture-web-dev-1: {ansible_host: 192.0.2.11}
    role_jump:
      hosts:
        fixture-jump: {ansible_host: 192.0.2.12}
    env_prod:
      hosts:
        fixture-web-prod-1:
    env_dev:
      hosts:
        fixture-web-dev-1:
    env_hub:
      hosts:
        fixture-jump:
EOF
}

# an19_guard_behaves: site.yml against the fixture (with the learner's venv; no Azure): limited to
# env_prod it fails on the guard before any connection; with -e confirm_prod=true it gets past
# the guard (and then can't reach the fake host); limited to dev it isn't stopped by the guard.
an19_guard_behaves() {
  local tmp out rc
  tmp="$(mktemp -d)"
  an19_fixture "$tmp/fixture.yml"
  rc=0
  out="$(an_run ansible-playbook site.yml -i "$tmp/fixture.yml" --limit env_prod 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "site.yml --limit env_prod without confirm_prod exited 0"
  elif grep -q "UNREACHABLE" <<<"$out"; then
    echo "site.yml --limit env_prod tried to connect before the guard stopped it"
    rc=0
  elif ! grep -qE '"assertion"|Assertion failed|evaluated_to' <<<"$out"; then
    echo "site.yml --limit env_prod failed, but not on an assert"
    rc=0
  fi
  [[ $rc -ne 0 ]] || { rm -rf "$tmp"; return 1; }
  out="$(an_run ansible-playbook site.yml -i "$tmp/fixture.yml" --limit env_prod -e confirm_prod=true 2>&1)" || true
  if grep -qE '"assertion"|Assertion failed|evaluated_to' <<<"$out" || ! grep -q "UNREACHABLE" <<<"$out"; then
    echo "with -e confirm_prod=true the run did not get past the guard"
    rm -rf "$tmp"
    return 1
  fi
  out="$(an_run ansible-playbook site.yml -i "$tmp/fixture.yml" --limit env_dev 2>&1)" || true
  rm -rf "$tmp"
  if grep -qE '"assertion"|Assertion failed|evaluated_to' <<<"$out" || ! grep -q "UNREACHABLE" <<<"$out"; then
    echo "a dev-only run was stopped by the guard"
    return 1
  fi
}
export -f an19_guard_files an19_guard_wired an19_env_prod an19_lb_dev_only an19_ci_prod_job an19_fixture an19_guard_behaves

check_code "a guard play asserts -e confirm_prod=true for env_prod hosts, in (or imported by) site.yml and deploy.yml" \
  'an19_guard_wired' \
  "write a guard (e.g. ansible/guard.yml: hosts: all, gather_facts: false, any_errors_fatal: true, an assert that confirm_prod | default(false) | bool when 'env_prod' in group_names) and import it first in site.yml and deploy.yml"

check_code "the inventory declares env_prod, and group_vars/env_prod.yml points at the prod vault" \
  'an19_env_prod' \
  "declare env_prod in a static inventory file (inventory/groups.yml, loaded through ansible.cfg's inventory list) and write group_vars/env_prod.yml: acme_env: prod, acme_kv_url: https://kv-$PREFIX-prod-$SUFFIX.vault.azure.net"

check_code "HAProxy's backends are the dev web servers only (role_web ∩ env_dev)" \
  'an19_lb_dev_only' \
  "build haproxy_backends from groups['role_web'] | intersect(groups['env_dev']): prod web servers must never join the dev load balancer"

check_code "ansible.yml: a prod job (environment: prod, --limit env_prod, -e confirm_prod=true); every other runner job limits to dev" \
  'an19_ci_prod_job' \
  "add job apply-prod (workflow_dispatch env=prod, runs-on [self-hosted, acme-jump], environment: prod, the fork guard) running site.yml --limit env_prod -e confirm_prod=true; give check, apply and drift --limit env_dev:env_hub"

an19_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "against a fixture inventory: prod without confirm_prod fails on the assert before any connection; with it, and dev-only, the guard lets the run through" \
  'an19_guard_behaves' \
  "cd ansible && ansible-playbook site.yml -i <inventory with a host in env_prod> --limit env_prod must fail at the guard's assert without trying to connect (gather_facts: false in the guard play)"

check "the inventory has the group env_prod (empty: the lab builds no prod VMs)" \
  'an_run ansible-inventory --graph 2>&1 | grep -qE "@env_prod:" && ! an_run ansible env_prod --list-hosts 2>&1 | grep -q "Could not match supplied host pattern"' \
  "cd ansible && ansible-inventory --graph must show @env_prod and ansible env_prod --list-hosts must not warn that the pattern matches nothing"

GRADE_TIMEOUT=480
check "a second run of site.yml (dev and hub) changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the guard and the dev-only backends must change nothing on the fleet"
GRADE_TIMEOUT="$an19_timeout"
