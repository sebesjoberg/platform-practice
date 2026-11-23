# an-03 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# Remote probes (read-only), run as root on every VM through the learner's inventory.
an03_sshd_hardened() {
  an_on_all 'sshd -T | grep -qx "passwordauthentication no" && sshd -T | grep -qx "permitrootlogin no"'
}
an03_ops_user() {
  local n
  n="$(an_host_count)"
  [[ "${n:-0}" -ge 3 ]] || return 1
  an_run ansible all -e ansible_user=ops -b -m ansible.builtin.shell -a 'id -nG ops | grep -qw sudo'
}
an03_updates_time() {
  an_on_all 'eval "$(apt-config shell UU APT::Periodic::Unattended-Upgrade)" && [ "$UU" = 1 ] && systemctl is-active -q chrony && [ "$(timedatectl show -p Timezone --value)" = Etc/UTC ]'
}
# an03_site_applies_base <file>: a play for hosts: all applies role base, in any common form:
# `- role: base`, `- base`, `roles: [base]`, `- { role: base }`, import_role/include_role name: base.
an03_site_applies_base() {
  local f=$1
  [[ -f "$f" ]] || return 1
  grep -qE "hosts:[[:space:]]*.?all.?[[:space:]]*$" "$f" || return 1
  grep -qE "^[[:space:]]*-[[:space:]]*.?base.?[[:space:]]*$|role:[[:space:]]*.?base([^[:alnum:]_.-]|$)|roles:[[:space:]]*\[([^]]*[[:space:],])?.?base.?([[:space:],]|\])" "$f" && return 0
  grep -qE "(import|include)_role:" "$f" && grep -qE "^[[:space:]]*name:[[:space:]]*.?base.?[[:space:]]*$" "$f"
}
export -f an03_sshd_hardened an03_ops_user an03_updates_time an03_site_applies_base

# The values themselves are proven live by sshd -T below, so any template style passes here
# (literal lines or a data-driven loop over a dict of options).
check_code "role base hardens sshd with a drop-in in sshd_config.d, validated by sshd -t, reloaded by a handler" \
  'r=ansible/roles/base && grep -rqE "/etc/ssh/sshd_config\.d/[^[:space:]\"]+\.conf" "$r/tasks" && grep -rqE "validate:[[:space:]]*.?(/usr/sbin/)?sshd -t -f %s" "$r/tasks" && grep -rqE "notify:" "$r/tasks" && compgen -G "$r/handlers/main.y*ml" >/dev/null' \
  "ansible/roles/base: a template/copy task writing /etc/ssh/sshd_config.d/<name>.conf with validate: /usr/sbin/sshd -t -f %s and notify, plus the handler in roles/base/handlers/main.yml"

check_code "role base: ops user from base_ops_user, unattended-upgrades, chrony, timezone" \
  'r=ansible/roles/base && grep -qsE "^base_ops_user:[[:space:]]*.?ops.?[[:space:]]*$" "$r"/defaults/main.y*ml && grep -rqE "unattended-upgrades" "$r" && grep -rqE "chrony" "$r" && grep -rqE "timezone" "$r/tasks"' \
  "ansible/roles/base needs the default base_ops_user: ops, and tasks for the ops user, unattended-upgrades, chrony and the timezone"

check_code "ansible/site.yml applies role base to all hosts" \
  'an03_site_applies_base ansible/site.yml' \
  "write ansible/site.yml: a play with hosts: all and become: true that applies the role base"

check "sshd on every VM: passwordauthentication no, permitrootlogin no (sshd -T)" \
  'an03_sshd_hardened' \
  "sudo sshd -T on each VM must print passwordauthentication no and permitrootlogin no: does the drop-in sort before 50-cloud-init.conf, and did the handler reload ssh?"

check "the ops user logs in with ~/.ssh/${PREFIX}_lab and sudoes without a password on every VM" \
  'an03_ops_user' \
  "cd ansible && ansible all -e ansible_user=ops -b -m ping must work on every VM (the web VMs through the jump host as ops too): user ops in group sudo, ~/.ssh/${PREFIX}_lab.pub authorized, NOPASSWD sudo"

check "unattended upgrades on, chrony running, timezone Etc/UTC on every VM" \
  'an03_updates_time' \
  "on each VM: apt-config dump APT::Periodic::Unattended-Upgrade must say \"1\", systemctl is-active chrony must say active, timedatectl must show Etc/UTC"

# Runs the learner's site.yml once more: on a converged fleet it changes nothing (that is what
# is graded), so this documented probe leaves the VMs as they are. Up to 5 minutes for 3 VMs.
an03_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=300
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM (a task that reports changed on every run isn't idempotent)"
GRADE_TIMEOUT="$an03_timeout"
