# an-13 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an13_mod: the module's file (ansible/library, or a collection's plugins/modules from an-14).
an13_mod() { an_module_file acme_app_setting; }

# an13_uses_module: a role's tasks or a playbook call the module (short name or FQCN).
an13_uses_module() {
  local r f
  while IFS= read -r r; do
    grep -rqsE "^[[:space:]]*(-[[:space:]]+)?([a-z0-9_]+\.[a-z0-9_]+\.)?acme_app_setting:" "$r/tasks" && return 0
  done < <(an_role_dirs)
  while IFS= read -r f; do
    grep -qE "^[[:space:]]*(-[[:space:]]+)?([a-z0-9_]+\.[a-z0-9_]+\.)?acme_app_setting:" "$f" && return 0
  done < <(an_playbooks)
  return 1
}

# an13_adhoc <host> <args> [ansible options]: run the module ad hoc with the learner's inventory,
# loaded from the directory of its file (works for ansible/library and a collection's modules).
an13_adhoc() {
  local m h=$1 a=$2
  shift 2
  m="$(an13_mod)" || return 1
  ANSIBLE_LIBRARY="$PWD/$(dirname "$m")" an_run ansible "$h" -m acme_app_setting -a "$a" "$@"
}

# an13_local_behaviour: the module against a scratch file on this machine (no inventory, no
# SSH): check mode reports changed and writes nothing, a real run writes, a second run is ok,
# other keys survive, absent removes.
an13_local_behaviour() {
  local tmp f out rc=0
  tmp="$(mktemp -d)"
  f="$tmp/settings.json"
  printf '{"build": "42"}\n' >"$f"
  run() { an13_adhoc localhost "path=$f $1" -i localhost, -c local "${@:2}" 2>&1; }
  out="$(run "key=features.flag value=on" --check --diff)" || rc=1
  grep -q "CHANGED" <<<"$out" || { echo "check mode does not report changed"; rc=1; }
  grep -q "flag" "$f" && { echo "check mode wrote the file"; rc=1; }
  out="$(run "key=features.flag value=on")" || rc=1
  { grep -q "CHANGED" <<<"$out" && grep -q '"flag"' "$f"; } || { echo "a real run did not write the key"; rc=1; }
  out="$(run "key=features.flag value=on")" || rc=1
  grep -q "SUCCESS" <<<"$out" || { echo "a second identical run is not ok (changed=false)"; rc=1; }
  grep -q '"build"' "$f" || { echo "the other key was lost"; rc=1; }
  out="$(run "key=features.flag state=absent")" || rc=1
  grep -q '"flag"' "$f" && { echo "state=absent did not remove the key"; rc=1; }
  rm -rf "$tmp"
  return "$rc"
}

# an13_check_mode_on_vm: on web-dev-1, a check-mode run with a new key reports changed, and the
# probe then finds the file unchanged (no grader_probe key) with the inventory's settings.
an13_check_mode_on_vm() {
  local out
  out="$(an13_adhoc "vm-$PREFIX-web-dev-1" "path=/etc/acme/settings.json key=grader_probe value=1" -b --check --diff 2>&1)" || return 1
  grep -q "CHANGED" <<<"$out" || { echo "the check-mode run did not report changed"; return 1; }
  an_probe role_web 2 app-settings.sh debug
}
export -f an13_mod an13_uses_module an13_adhoc an13_local_behaviour an13_check_mode_on_vm

check_code "module acme_app_setting: argument spec with check mode support" \
  'm="$(an13_mod)" && grep -qE "AnsibleModule\(" "$m" && grep -qE "argument_spec" "$m" && grep -qE "supports_check_mode[[:space:]]*=[[:space:]]*True" "$m" && grep -qE "\.check_mode" "$m"' \
  "write ansible/library/acme_app_setting.py: AnsibleModule(argument_spec=..., supports_check_mode=True), and nothing written when module.check_mode is set"

check_code "module acme_app_setting: DOCUMENTATION, EXAMPLES and RETURN, and a diff in diff mode" \
  'm="$(an13_mod)" && grep -qE "^DOCUMENTATION[[:space:]]*=" "$m" && grep -qE "^EXAMPLES[[:space:]]*=" "$m" && grep -qE "^RETURN[[:space:]]*=" "$m" && grep -qE "_diff|diff_mode" "$m" && grep -qE "[\"'"'"']before[\"'"'"']|before=" "$m"' \
  "the module needs DOCUMENTATION, EXAMPLES and RETURN blocks (ansible-doc acme_app_setting renders them) and returns diff=dict(before=..., after=...) when module._diff is set"

check_code "the settings are applied with the module (a role's tasks or a playbook)" \
  'an13_uses_module' \
  "use acme_app_setting in role app_env (or a playbook) to set app_env_settings in /etc/acme/settings.json"

an13_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=120
check "the module on a scratch file: check mode writes nothing, a run writes, a second run is ok, absent removes" \
  'an13_local_behaviour' \
  "ANSIBLE_LIBRARY=library ansible localhost -i localhost, -c local -m acme_app_setting -a \"path=/tmp/s.json key=a.b value=1\" with and without --check (from ansible/, venv active): check mode reports changed and leaves the file alone, a second real run reports ok"

GRADE_TIMEOUT=180
check "web VMs: /etc/acme/settings.json root:acme 0640 with log_level debug and features.maintenance_page false; a --check run changed nothing" \
  'an13_check_mode_on_vm' \
  "run site.yml; the module must report changed in --check mode without writing (sudo cat /etc/acme/settings.json on the web VMs shows no grader_probe)"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the module must report changed only when a value really changes"
GRADE_TIMEOUT="$an13_timeout"
