# an-07 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# Files under ansible/ that call the Key Vault secret lookup.
an07_lookup_files() {
  grep -rlE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible \
    "azure\.azcollection\.azure_keyvault_secret" ansible 2>/dev/null
}

# an07_no_log_role: a role whose files mention app.env writes with no_log: true (or a playbook
# does).
an07_no_log_role() {
  local r
  while IFS= read -r r; do
    grep -rqsF --exclude-dir=molecule "app.env" "$r" && grep -rqsE "no_log:[[:space:]]*.?true" "$r/tasks" && return 0
  done < <(an_role_dirs)
  local f
  while IFS= read -r f; do
    grep -qF "app.env" "$f" && grep -qE "no_log:[[:space:]]*.?true" "$f" && return 0
  done < <(an_playbooks)
  return 1
}

# The current value, read the way the grader is allowed to: your az login.
an07_value() {
  az keyvault secret show --vault-name "$(an_kv_name)" -n app-greeting --query value -o tsv
}

# an07_env_ok: both web VMs have /etc/acme/app.env root:acme 0640 with APP_GREETING = the vault's
# current value. Only its SHA-256 goes to the VMs.
an07_env_ok() {
  local v
  v="$(an07_value)" && [[ -n "$v" ]] || return 1
  an_probe role_web 2 app-env.sh "$(printf '%s' "$v" | sha256sum | cut -d' ' -f1)"
}

# an07_no_leak: the value is in no file of the repo (tracked or untracked, ignored files aside),
# was never committed on any branch, and isn't in the Ansible log file if one is configured. The
# value setup created (snapshot) must not be in the working tree either.
an07_no_leak() {
  local v s log
  v="$(an07_value)" && [[ -n "$v" ]] || return 1
  if git grep -qF --untracked -e "$v"; then
    echo "the value is in a file of the repo"
    return 1
  fi
  if [[ -n "$(git log --all -S"$v" --format=%h)" ]]; then
    echo "the value was committed: rotate the secret (az keyvault secret set) and redeploy"
    return 1
  fi
  s="$(head -n1 "$LAB_HOME/snapshots/an-07.value" 2>/dev/null || true)"
  if [[ -n "$s" && "$s" != "$v" ]] && git grep -qF --untracked -e "$s"; then
    echo "setup's value is in a file of the repo"
    return 1
  fi
  log="$(an_run ansible-config dump --only-changed 2>/dev/null | sed -nE 's/^DEFAULT_LOG_PATH\([^)]*\) = //p' | head -n1)"
  [[ -z "$log" || "$log" == /* ]] || log="ansible/$log"
  if [[ -n "$log" && -f "$log" ]] && grep -qF -e "$v" "$log"; then
    echo "the value is in the Ansible log $log: no_log on every task it flows through"
    return 1
  fi
}
export -f an07_lookup_files an07_no_log_role an07_value an07_env_ok an07_no_leak

check_code "the secret app-greeting is read with the azure.azcollection.azure_keyvault_secret lookup" \
  'files="$(an07_lookup_files)" && [[ -n "$files" ]] && grep -qF "app-greeting" $files' \
  "look up the secret app-greeting with lookup('azure.azcollection.azure_keyvault_secret', 'app-greeting', vault_url=...) in ansible/ (e.g. inventory/group_vars/role_web.yml)"

check_code "the lookup authenticates through a variable (cli now, msi on the runner later)" \
  'files="$(an07_lookup_files)" && [[ -n "$files" ]] && grep -qE "auth_source[[:space:]]*=[[:space:]]*\(?[A-Za-z_]" $files' \
  "pass auth_source=<a variable> (e.g. acme_kv_auth_source, cli in group_vars/all.yml) to the lookup, not a literal 'cli': CI switches it to msi with -e"

check_code "the task that writes app.env has no_log: true" \
  'an07_no_log_role' \
  "set no_log: true on the task that writes /etc/acme/app.env (in role app_env): without it --diff and -v print the value"

check_code "role app_env has a Molecule scenario (docker, converge, verify, idempotence kept)" \
  'an_molecule_scenario app_env' \
  "create ansible/roles/app_env/molecule/default; converge.yml passes a stub value instead of the Key Vault lookup"

an07_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "both web VMs: /etc/acme/app.env is root:acme 0640, APP_GREETING = the secret's value in $(an_kv_name)" \
  'an07_env_ok' \
  "on both web VMs /etc/acme/app.env must be owned root:acme, mode 0640, with a line APP_GREETING=<value of app-greeting in $(an_kv_name)>; rotated the secret? run site.yml again"

check "the value is in no file and no commit of the repo, nor in the Ansible log" \
  'an07_no_leak' \
  "the value of app-greeting must appear in no file (git grep --untracked) and no commit (git log --all -S<value>) of your repo, nor in the file log_path points to. Committed it? Rotate the secret, redeploy."

GRADE_TIMEOUT=900
check "molecule test passes for role app_env" \
  'an_molecule_test app_env' \
  "cd ansible/roles/app_env && molecule test (venv active, Docker running) must pass"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM"
GRADE_TIMEOUT="$an07_timeout"
