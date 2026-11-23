# an-06 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# validate: on one line naming nginx, -t and %s: `nginx -t -c %s` on the whole nginx.conf, or a
# wrapper that includes the snippet %s into a complete config.
check_code "role nginx writes its configuration with validate: nginx -t on %s, and reloads through a handler" \
  'r=ansible/roles/nginx && [[ -d "$r/tasks" ]] && find "$r/tasks" -type f -name "*.y*ml" -exec awk "/validate:/ && /nginx/ && /[[:space:]]-t/ && /%s/ { f = 1 } END { exit !f }" {} + && grep -rqE "notify:" "$r/tasks" && grep -rqsiE "reload" "$r/handlers"' \
  "ansible/roles/nginx: the template task gets validate: /usr/sbin/nginx -t -c %s (on a complete configuration, or a wrapper that includes the snippet %s into one) and notify:, and a handler in roles/nginx/handlers reloads nginx"

check_code "a play for role_web applies role nginx" \
  'an_play_applies role_web nginx' \
  "add a second play to ansible/site.yml: hosts: role_web, become: true, roles: [nginx]"

check_code "role nginx has a Molecule scenario (docker, converge, verify, idempotence kept)" \
  'an_molecule_scenario nginx' \
  "create ansible/roles/nginx/molecule/default (molecule.yml with the docker driver, converge.yml, verify.yml), as for role base in an-05"

an06_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "each web VM: nginx active, nginx -t passes, port 80 names the host and dev" \
  'an_probe role_web 2 web-page.sh dev' \
  "on both web VMs: systemctl is-active nginx, sudo nginx -t, and curl -s http://127.0.0.1/ must show the VM's hostname and dev (cd ansible && ansible role_web -b -m ansible.builtin.shell -a \"curl -s localhost\")"

GRADE_TIMEOUT=900
check "molecule test passes for role nginx" \
  'an_molecule_test nginx' \
  "cd ansible/roles/nginx && molecule test (venv active, Docker running) must pass: converge, idempotence, verify"

# Runs the learner's site.yml once more: on a converged fleet it changes nothing (documented probe).
GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM"
GRADE_TIMEOUT="$an06_timeout"
