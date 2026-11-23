# shellcheck shell=bash
# Check API, sourced by the grader (in a subshell) before a task's checks.sh.
#   check      "<name>" '<cmd>' "<reason>"   needs cloud/GitHub (preflight first)
#   check_code "<name>" '<cmd>' "<reason>"   offline-safe, reads LIVE_DIR/MODULES_DIR only
# Each command runs immediately: bash -o pipefail -c, cwd LIVE_DIR, stdin /dev/null,
# ${GRADE_TIMEOUT:-60}s timeout. Results are appended to $GRADE_RESULTS (P/F lines).

# Decided once, here: inside $(...) stdout is a pipe, so -t 1 must not be tested there.
_GRADE_COLOR=0
if [[ ( -t 1 || -n "${GRADE_FORCE_COLOR:-}" ) && -z "${NO_COLOR:-}" ]]; then _GRADE_COLOR=1; fi

_grade_color() { # _grade_color <code> <text>
  if [[ $_GRADE_COLOR -eq 1 ]]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

_grade_run() { # _grade_run <name> <cmd> <reason>
  local name=$1 cmd=$2 reason=$3 out rc
  out="$(mktemp "${TMPDIR:-/tmp}/grade-out.XXXXXX")"
  rc=0
  if [[ -z "${LIVE_DIR:-}" ]]; then
    reason="LIVE_DIR not set"
    rc=1
  else
    (
      cd "$LIVE_DIR" || exit 126
      exec timeout -k 2 "${GRADE_TIMEOUT:-60}" bash -o pipefail -c "$cmd" </dev/null >"$out" 2>&1
    ) || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    echo P >>"$GRADE_RESULTS"
    printf '%s  %s\n' "$(_grade_color 32 '✓ PASS')" "$name"
  else
    echo F >>"$GRADE_RESULTS"
    printf '%s  %s\n' "$(_grade_color 31 '✗ FAIL')" "$name"
    if [[ $rc -eq 124 || $rc -eq 137 ]]; then
      printf '    → timed out\n'
    else
      printf '    → %s\n' "$reason"
    fi
  fi
  rm -f "$out"
}

check() {
  [[ "${GRADE_OFFLINE:-0}" == 1 ]] && return 0
  grade_preflight
  _grade_run "$@"
}

check_code() {
  _grade_run "$@"
}
