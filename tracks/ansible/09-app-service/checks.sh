# an-09 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an09_health_ok: both web VMs run acme-hello.service (not as root, systemd-analyze security below
# 5.0) and answer "ok <app_version>" on 127.0.0.1:8080/health and through nginx, where
# <app_version> is what the learner's inventory resolves for the first web VM.
an09_health_ok() {
  local v
  v="$(an_hostvar "vm-$PREFIX-web-dev-1" app_version)"
  [[ -n "$v" ]] || return 1
  an_probe role_web 2 app-health.sh "$v"
}
export -f an09_health_ok

AN09_R=ansible/roles/acme_hello
export AN09_R

check_code "role acme_hello ships the app (Python, http.server) in its files/" \
  'compgen -G "$AN09_R/files/releases/*/*.py" >/dev/null && grep -rqE "http\.server" "$AN09_R/files"' \
  "copy the releases from ~/.platform-lab/starter/an-09/releases into ansible/roles/acme_hello/files/releases/<version>/"

check_code "the role installs acme-hello.service with its own user and hardening directives" \
  'grep -rqsF "acme-hello.service" "$AN09_R/tasks" "$AN09_R/handlers" "$AN09_R/templates" "$AN09_R/files" && grep -rqsE "^[[:space:]]*(User=|DynamicUser=(yes|true))" "$AN09_R/templates" "$AN09_R/files" && ! grep -rqsE "^[[:space:]]*User=(root|0)[[:space:]]*$" "$AN09_R/templates" "$AN09_R/files" && grep -rqsE "^[[:space:]]*(NoNewPrivileges=yes|ProtectSystem=|CapabilityBoundingSet=)" "$AN09_R/templates" "$AN09_R/files"' \
  "template /etc/systemd/system/acme-hello.service in role acme_hello: User= a dedicated user (or DynamicUser=yes), plus hardening (NoNewPrivileges, ProtectSystem, CapabilityBoundingSet, ...)"

check_code "the role waits for /health with ansible.builtin.uri and until:" \
  'grep -rqE "ansible\.builtin\.uri:" "$AN09_R/tasks" && grep -rqF "/health" "$AN09_R/tasks" && grep -rqE "^[[:space:]]*until:" "$AN09_R/tasks"' \
  "after a (re)start, an ansible.builtin.uri task on http://127.0.0.1:8080/health with until:/retries:/delay: that waits for ok <version>"

check_code "app_version picks the release" \
  'grep -rqsE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible "^[[:space:]]*app_version:" ansible && grep -rqsE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible "\{\{[[:space:]]*app_version[[:space:]]*\}\}" ansible' \
  "define app_version (e.g. \"1.0.0\" in inventory/group_vars/role_web.yml) and feed it to the role (acme_hello_version: \"{{ app_version }}\")"

check_code "a play for role_web applies role acme_hello" \
  'an_play_applies role_web acme_hello' \
  "add role acme_hello to the web servers' play in ansible/site.yml (before nginx, after app_env)"

check_code "role acme_hello has a Molecule scenario (docker, converge, verify, idempotence kept)" \
  'an_molecule_scenario acme_hello' \
  "create ansible/roles/acme_hello/molecule/default (switch off what an unprivileged container can't run, with a documented role variable)"

an09_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "both web VMs: acme-hello.service active, not root, hardened, /health = ok <app_version> (direct and through nginx)" \
  'an09_health_ok' \
  "on both web VMs: systemctl is-active acme-hello, systemctl show -p User acme-hello not root, systemd-analyze security acme-hello.service below 5.0, curl -s localhost:8080/health and curl -s localhost/health print ok <app_version>"

GRADE_TIMEOUT=900
check "molecule test passes for role acme_hello" \
  'an_molecule_test acme_hello' \
  "cd ansible/roles/acme_hello && molecule test (venv active, Docker running) must pass"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM"
GRADE_TIMEOUT="$an09_timeout"
