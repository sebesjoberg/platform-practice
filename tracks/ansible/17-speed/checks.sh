# an-17 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN17_CFG=ansible/ansible.cfg

# an17_cfg <key>: the value of <key> in ansible.cfg (first match, any section), trimmed.
an17_cfg() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^#;]*[^#;[:space:]]).*/\1/p" "$AN17_CFG" | head -n1
}

# an17_fact_dir: the fact cache directory as configured, relative to ansible/ when relative.
an17_fact_dir() {
  local d
  d="$(an17_cfg fact_caching_connection)"
  [[ -n "$d" ]] || return 1
  d="${d#./}"
  echo "${d%/}"
}

# an17_fact_cache: jsonfile fact cache in a directory inside ansible/ whose top-level name is
# gitignored (ansible/.gitignore or the repo's), and gathering = smart.
an17_fact_cache() {
  local d top
  [[ "$(an17_cfg fact_caching)" =~ ^(ansible\.builtin\.)?jsonfile$ ]] || { echo "fact_caching is not jsonfile"; return 1; }
  [[ "$(an17_cfg gathering)" == smart ]] || { echo "gathering is not smart"; return 1; }
  d="$(an17_fact_dir)" || { echo "no fact_caching_connection"; return 1; }
  [[ "$d" != /* && "$d" != ~* && "$d" != ..* ]] || { echo "the fact cache must live inside ansible/ (a relative path)"; return 1; }
  top="${d%%/*}"
  grep -qsxE "[[:space:]]*/?(ansible/)?$top/?[[:space:]]*" ansible/.gitignore .gitignore || { echo "$top/ is not gitignored"; return 1; }
}

# an17_ssh: pipelining on, ControlPersist kept, and IdentitiesOnly still in ssh_args.
an17_ssh() {
  [[ "$(an17_cfg pipelining | tr '[:upper:]' '[:lower:]')" =~ ^(true|yes|1|on)$ ]] || { echo "pipelining is off"; return 1; }
  an17_cfg ssh_args | grep -qE "ControlPersist=" || { echo "ssh_args lost ControlPersist"; return 1; }
  an17_cfg ssh_args | grep -qE "IdentitiesOnly=yes" || { echo "ssh_args lost IdentitiesOnly=yes"; return 1; }
}

# an17_no_cached_secrets: no role or playbook caches set_fact results (cacheable: true would put
# them, the TLS bundle for instance, into the fact cache files).
an17_no_cached_secrets() {
  local r f
  while IFS= read -r r; do
    ! grep -rqsE --exclude-dir=molecule "cacheable:[[:space:]]*.?(true|yes)" "$r" || { echo "$r caches a set_fact"; return 1; }
  done < <(an_role_dirs)
  while IFS= read -r f; do
    ! grep -qE "cacheable:[[:space:]]*.?(true|yes)" "$f" || { echo "$f caches a set_fact"; return 1; }
  done < <(an_playbooks)
}

# an17_cache_filled: after the grader's site.yml run, the fact cache holds a file per lab VM.
an17_cache_filled() {
  local d h
  d="ansible/$(an17_fact_dir)" || return 1
  for h in "vm-$PREFIX-jump" "vm-$PREFIX-web-dev-1" "vm-$PREFIX-web-dev-2"; do
    [[ -s "$d/$h" ]] || { echo "no cached facts for $h in $d"; return 1; }
  done
}
export -f an17_cfg an17_fact_dir an17_fact_cache an17_ssh an17_no_cached_secrets an17_cache_filled

check_code "fact caching: jsonfile in a gitignored directory inside ansible/, gathering = smart" \
  'an17_fact_cache' \
  "in ansible.cfg [defaults]: gathering = smart, fact_caching = ansible.builtin.jsonfile, fact_caching_connection = ./.facts (and .facts/ in ansible/.gitignore), fact_caching_timeout"

check_code "SSH: pipelining on, ControlPersist and IdentitiesOnly=yes kept in ssh_args" \
  'an17_ssh' \
  "in ansible.cfg [ssh_connection]: pipelining = True, and keep -o ControlPersist=... and -o IdentitiesOnly=yes in ssh_args (it replaces Ansible's defaults)"

check_code "no set_fact is cacheable (secrets stay out of the fact cache)" \
  'an17_no_cached_secrets' \
  "remove cacheable: true from set_fact tasks: with fact caching on, those values (nginx's TLS bundle, say) would be written to the cache files"

# Runs the learner's site.yml once more (documented probe); it must still change nothing, and it
# fills the fact cache.
an17_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host (with pipelining)" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second run must report changed=0 with the new settings (pipelining needs sudo without requiretty)"
GRADE_TIMEOUT="$an17_timeout"

check "the fact cache holds the facts of the three VMs" \
  'an17_cache_filled' \
  "after ansible-playbook site.yml, the fact cache directory (fact_caching_connection) must hold one JSON file per VM (named after the inventory host)"
