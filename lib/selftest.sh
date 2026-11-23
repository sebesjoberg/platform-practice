# shellcheck shell=bash
# Selftest: ./lab.sh selftest [--offline] [track] [--from id] [--to id]
#   --offline  proves the references match the checks without Azure (build_reference + grade offline)
#   (default)  live: setup -> grade must fail -> catchup --yes -> grade must pass. Costs money.

# selftest_fixture_env: exports the fixture config used to render references offline.
# Same values as tests/test_helper.bash.
selftest_fixture_env() {
  export PREFIX=acme SUFFIX=abc123 LOCATION=swedencentral
  export SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
  export TENANT_ID=11111111-1111-1111-1111-111111111111
  export GH_OWNER=learner LIVE_REPO=acme-platform MODULES_REPO=acme-terraform-modules
  export LEARNER_IP=203.0.113.10 OWNER_TAG=learner
}

# _selftest_select <track> <from> <to>: fills SELFTEST_IDS (main shell, so errors exit before any work).
_selftest_select() {
  local track=$1 from=$2 to=$3 id i=0 fi_=-1 ti=-1
  local -a all=()
  SELFTEST_IDS=()
  [[ -z "$track" || -d "$TRACKS_DIR/$track" ]] || die 2 "selftest: unknown track: $track"
  while IFS= read -r id; do
    all+=("$id")
    [[ -n "$from" && "$id" == "$from" ]] && fi_=$i
    [[ -n "$to" && "$id" == "$to" ]] && ti=$i
    i=$((i + 1))
  done < <(task_ids "$track")
  [[ -z "$from" || $fi_ -ge 0 ]] || die 2 "selftest: --from $from not found"
  [[ -z "$to" || $ti -ge 0 ]] || die 2 "selftest: --to $to not found"
  [[ $fi_ -ge 0 ]] || fi_=0
  [[ $ti -ge 0 ]] || ti=$((${#all[@]} - 1))
  [[ $ti -ge $fi_ ]] || die 2 "selftest: --to $to comes before --from $from"
  for ((i = fi_; i <= ti; i++)); do SELFTEST_IDS+=("${all[i]}"); done
  return 0
}

# _selftest_grade <id> <live> <modules> <log>: offline grade against a built tree; 0 = all pass.
_selftest_grade() {
  local id=$1 live=$2 mods=$3 log=$4
  mkdir -p "$live" "$mods"
  (
    GRADE_TMP="$(mktemp -d)"
    trap 'rm -rf "$GRADE_TMP"' EXIT
    export LIVE_DIR="$live" MODULES_DIR="$mods"
    grade_task "$id" offline
  ) >"$log" 2>&1
}

# _selftest_offline_one <id> <work>: prints one table row; returns 1 on a violation.
_selftest_offline_one() {
  local id=$1 work=$2 d b a brc=0 arc=0 note="" n
  local -a replay=()
  d="$(task_dir "$id")"
  if ! grep -Eq '^[[:space:]]*check_code[[:space:]]' "$d/checks.sh"; then
    printf '%-10s %-8s %-8s %s\n' "$id" "n/a" "n/a" "no check_code"
    return 0
  fi
  mapfile -t replay < <(_replay_ids "$id")
  n=${#replay[@]}

  b="$work/before"
  a="$work/after"
  rm -rf "$b" "$a"
  # before = exactly the replay without this task (the previous task's reference alone may differ)
  (replay_into "$b" "${replay[@]:0:n-1}") || return 1
  _selftest_grade "$id" "$b/live" "$b/modules" "$work/before.log" || brc=$?

  (build_reference "$id" "$a") || return 1
  _selftest_grade "$id" "$a/live" "$a/modules" "$work/after.log" || arc=$?

  [[ $brc -eq 0 ]] && note="a check passes before the task"
  [[ $arc -ne 0 ]] && note="${note:+$note; }a check fails after the task"
  printf '%-10s %-8s %-8s %s\n' "$id" "$([[ $brc -ne 0 ]] && echo fail || echo PASS)" \
    "$([[ $arc -eq 0 ]] && echo pass || echo FAIL)" "${note:-ok}"
  if [[ $brc -eq 0 ]]; then
    sed 's/^/    before: /' "$work/before.log"
  fi
  if [[ $arc -ne 0 ]]; then
    sed 's/^/    after: /' "$work/after.log"
  fi
  [[ -z "$note" ]]
}

_selftest_offline() {
  local track=$1 from=$2 to=$3 id work bad=0 count=0
  selftest_fixture_env
  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
  printf '%-10s %-8s %-8s %s\n' id before after result
  _selftest_select "$track" "$from" "$to"
  for id in "${SELFTEST_IDS[@]}"; do
    count=$((count + 1))
    _selftest_offline_one "$id" "$work" || bad=$((bad + 1))
  done
  [[ $count -gt 0 ]] || die 1 "selftest: no tasks selected"
  if [[ $bad -gt 0 ]]; then
    echo "selftest offline: $bad of $count task(s) violate the contract" >&2
    return 1
  fi
  echo "selftest offline: $count task(s) ok"
}

# _selftest_clean_trees <dir>...: discard uncommitted changes and untracked files in each dir that
# is a git repo (reset --hard, clean -fd; ignored files stay). setup.sh starters (tf-05, tf-19,
# tf-21, tf-25, ...) may write files, and catchup rightly refuses a dirty tree. Only the live
# selftest does this: it runs on throwaway-prefix repos. A learner's catchup keeps refusing.
_selftest_clean_trees() {
  local d
  for d in "$@"; do
    [[ -n "$d" && -d "$d/.git" ]] || continue
    git -C "$d" reset -q --hard
    git -C "$d" clean -q -fd
  done
}

_selftest_live() {
  local track=$1 from=$2 to=$3 id d rc
  [[ "${SELFTEST_I_HAVE_PERMISSION:-}" == 1 ]] ||
    die 8 "live selftest creates real Azure resources and costs money; set SELFTEST_I_HAVE_PERMISSION=1 to run it"
  load_config
  need az gh terraform git timeout
  _selftest_select "$track" "$from" "$to"
  for id in "${SELFTEST_IDS[@]}"; do
    d="$(task_dir "$id")"
    echo "== $id: setup"
    if [[ -f "$d/setup.sh" ]]; then
      bash "$d/setup.sh" || die 1 "selftest: setup of $id failed"
    fi
    rc=0
    grade_quiet "$id" || rc=$?
    [[ $rc -eq 1 ]] || die 1 "selftest: $id: grade before catchup should fail (status $rc)"
    echo "== $id: fails before (ok), catchup"
    _selftest_clean_trees "${LIVE_DIR:-}" "${MODULES_DIR:-}"
    _catchup "$id" 1
    GRADE_TMP="$(mktemp -d)"
    if ! grade_task "$id" normal; then
      rm -rf "$GRADE_TMP"
      die 1 "selftest: $id: grade after catchup should pass ($GRADE_PASSED/$GRADE_TOTAL)"
    fi
    rm -rf "$GRADE_TMP"
    echo "== $id: ok"
  done
  echo "selftest: all tasks ok"
}

cmd_selftest() {
  local offline=0 track="" from="" to=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --offline) offline=1 ;;
      --from) from=${2:?--from needs an id}; shift ;;
      --to) to=${2:?--to needs an id}; shift ;;
      -*) die 2 "selftest: unknown option $1" ;;
      *) track=$1 ;;
    esac
    shift
  done
  if [[ $offline -eq 1 ]]; then
    _selftest_offline "$track" "$from" "$to"
  else
    _selftest_live "$track" "$from" "$to"
  fi
}
