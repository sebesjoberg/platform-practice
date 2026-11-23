# an-12 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN12_SCRIPT=ansible/bin/drift-check.sh

# an12_fake_dir <dir>: an ansible-playbook stand-in in <dir> that records its arguments in
# $AN12_ARGS and prints a PLAY RECAP for three hosts (web-dev-1 with changed=$AN12_CHANGED,
# web-dev-2 with unreachable=$AN12_UNREACHABLE), then exits $AN12_RC.
an12_fake_dir() {
  cat >"$1/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AN12_ARGS"
echo "TASK [nginx : Write the nginx configuration] ****"
echo
echo "PLAY RECAP *********************************************************************"
echo "vm-x-jump                  : ok=12   changed=0    unreachable=0    failed=0    skipped=3    rescued=0    ignored=0"
echo "vm-x-web-dev-1             : ok=30   changed=${AN12_CHANGED:-0}    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0"
echo "vm-x-web-dev-2             : ok=28   changed=0    unreachable=${AN12_UNREACHABLE:-0}    failed=0    skipped=2    rescued=0    ignored=0"
exit "${AN12_RC:-0}"
EOF
  chmod +x "$1/ansible-playbook"
}

# an12_script_behaves: the learner's drift-check.sh, run against the stand-in (no inventory, no
# SSH): exit 0 on a clean recap, non-zero on drift and on an unreachable host; it runs
# ansible-playbook in check mode with diffs and passes its own arguments on.
an12_script_behaves() {
  local tmp rc=0
  [[ -x "$AN12_SCRIPT" ]] || { echo "$AN12_SCRIPT is missing or not executable"; return 1; }
  tmp="$(mktemp -d)"
  an12_fake_dir "$tmp"
  export AN12_ARGS="$tmp/args"
  if ! PATH="$tmp:$PATH" "$AN12_SCRIPT" -e an12_probe=1 >/dev/null 2>&1; then
    echo "exits non-zero on a clean recap"
    rc=1
  fi
  if AN12_CHANGED=3 PATH="$tmp:$PATH" "$AN12_SCRIPT" >/dev/null 2>&1; then
    echo "exits 0 although a host has changed=3"
    rc=1
  fi
  if AN12_UNREACHABLE=1 AN12_RC=4 PATH="$tmp:$PATH" "$AN12_SCRIPT" >/dev/null 2>&1; then
    echo "exits 0 although a host was unreachable"
    rc=1
  fi
  if ! grep -qE "(^| )(--check|-C)( |$)" "$AN12_ARGS" 2>/dev/null || ! grep -qE "(^| )(--diff|-D)( |$)" "$AN12_ARGS"; then
    echo "does not run ansible-playbook with --check --diff"
    rc=1
  fi
  if ! grep -qF "an12_probe=1" "$AN12_ARGS" 2>/dev/null; then
    echo "does not pass its arguments on to ansible-playbook"
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# an12_shellcheck: shellcheck is clean, where it is installed (it is not one of the lab's tools).
an12_shellcheck() {
  bash -n "$AN12_SCRIPT" || return 1
  ! command -v shellcheck >/dev/null || shellcheck "$AN12_SCRIPT"
}
export -f an12_fake_dir an12_script_behaves an12_shellcheck

check_code "ansible/bin/drift-check.sh: executable, valid bash (shellcheck-clean where installed)" \
  'an12_shellcheck' \
  "write ansible/bin/drift-check.sh (#!/usr/bin/env bash, chmod +x, git update-index --chmod=+x on Windows); bash -n and shellcheck must pass"

check_code "drift-check.sh runs site.yml --check --diff, passes its arguments on, exits 0 only without drift" \
  'an12_script_behaves' \
  "drift-check.sh must call ansible-playbook from PATH with site.yml --check --diff \"\$@\", read the PLAY RECAP and exit 0 when every host has changed=0, non-zero on changed>0 and on failed or unreachable hosts (the grader runs it against a stand-in ansible-playbook)"

check_code "role acme_hello's health wait doesn't break check mode" \
  'grep -rqsE --exclude-dir=molecule "ansible_check_mode|check_mode:[[:space:]]*.?false" "$(an_role_dir acme_hello)/tasks"' \
  "in --check mode the uri task is skipped and its until: expression has no status to look at, which fails the run: give it when: not ansible_check_mode (or check_mode: false, if you want it to really ask)"

an12_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "both web VMs: nginx active, nginx -t passes, port 80 serves the host's page" \
  'an_probe role_web 2 web-page.sh dev' \
  "on both web VMs systemctl is-active nginx, sudo nginx -t, curl -s localhost (vm-$PREFIX-web-dev-2 was changed by hand: run site.yml)"

GRADE_TIMEOUT=480
check "drift-check.sh finds no drift: the whole fleet matches the repo again" \
  'an_run bin/drift-check.sh' \
  "cd ansible && bin/drift-check.sh must exit 0: every host changed=0 in check mode (it shows the diff of what still differs; run site.yml to put it back)"
GRADE_TIMEOUT="$an12_timeout"
