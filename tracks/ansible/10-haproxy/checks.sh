# an-10 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an10_backends_dynamic: something under ansible/ (roles, inventory, playbooks) takes the web
# servers from the inventory group role_web, and no backend address is written down: no `server`
# line in role haproxy's templates with an IPv4 literal, and no IPv4 literal in role haproxy's
# defaults/vars or the jump host's variables other than 0.0.0.0 and 127.x (bind addresses).
an10_backends_dynamic() {
  local ips r
  r="$(an_role_dir haproxy)" || r=ansible/roles/haproxy
  grep -rqsE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible --exclude-dir=molecule \
    "groups\[.?role_web.?\]|groups\.role_web" ansible || return 1
  ! grep -rqsE "^[[:space:]]*server[[:space:]]+[^[:space:]]+[[:space:]]+([0-9]{1,3}\.){3}[0-9]{1,3}" \
    "$r/templates" "$r/files" || return 1
  ips="$(grep -rhosE "([0-9]{1,3}\.){3}[0-9]{1,3}" "$r/defaults" "$r/vars" \
    ansible/inventory/group_vars/role_jump* ansible/inventory/group_vars/env_hub* ansible/inventory/host_vars 2>/dev/null || true)"
  [[ -z "$ips" ]] || ! grep -vqE "^(0\.0\.0\.0|127\.[0-9.]+)$" <<<"$ips"
}
export -f an10_backends_dynamic

check_code "role haproxy: config validated with haproxy -c, a backend web, the admin socket at level admin" \
  'r="$(an_role_dir haproxy)" && [[ -n "$r" ]] && grep -rqE "validate:[^#]*haproxy[^#]*[[:space:]]-c" "$r/tasks" && grep -rqsF "/run/haproxy/admin.sock" "$r" && grep -rqE "stats[[:space:]]+socket[^#]*level[[:space:]]+admin" "$r/templates" && grep -rqsE "backend[[:space:]]+web([[:space:]]|$)|_backend_name:[[:space:]]*.?web.?[[:space:]]*$" "$r/templates" "$r/defaults"' \
  "ansible/roles/haproxy: template /etc/haproxy/haproxy.cfg with validate: /usr/sbin/haproxy -c -f %s, a backend named web, and stats socket /run/haproxy/admin.sock mode 660 group haproxy level admin"

check_code "a play for role_jump applies role haproxy" \
  'an_play_applies role_jump haproxy' \
  "add a third play to ansible/site.yml: hosts: role_jump, become: true, roles: [haproxy] (after the web servers' play)"

check_code "the backends come from the inventory group role_web, no IP literals" \
  'an10_backends_dynamic' \
  "build the server list from groups['role_web'] and each host's private_ipv4_addresses (e.g. in inventory/group_vars/role_jump.yml); no backend IP addresses in role haproxy or the jump host's variables (0.0.0.0 and 127.x bind addresses are fine)"

check_code "role haproxy has a Molecule scenario (docker, converge, verify, idempotence kept)" \
  'an_molecule_scenario haproxy' \
  "create ansible/roles/haproxy/molecule/default (stand-in backends, e.g. python3 -m http.server in prepare.yml)"

an10_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "on the jump host: HAProxy valid and running, admin socket 660 group haproxy at level admin, 10 requests reach both web VMs" \
  'an_probe role_jump 1 haproxy.sh "vm-$PREFIX-web-dev-1" "vm-$PREFIX-web-dev-2"' \
  "on the jump host: systemctl is-active haproxy, sudo haproxy -c -f /etc/haproxy/haproxy.cfg, backend web, /run/haproxy/admin.sock mode 660 group haproxy (level admin), and for i in \$(seq 10); do curl -s localhost; done must show both vm-$PREFIX-web-dev-1 and vm-$PREFIX-web-dev-2"

GRADE_TIMEOUT=900
check "molecule test passes for role haproxy" \
  'an_molecule_test haproxy' \
  "cd ansible/roles/haproxy && molecule test (venv active, Docker running) must pass"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM"
GRADE_TIMEOUT="$an10_timeout"
