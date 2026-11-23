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

# _selftest_ids <track> <from> <to>: the task ids in range, one per line.
_selftest_ids() {
  local track=$1 from=$2 to=$3 id on=1 seen_from=0 seen_to=0
  [[ -z "$track" || -d "$TRACKS_DIR/$track" ]] || die 2 "selftest: unknown track: $track"
  [[ -z "$from" ]] || on=0
  while IFS= read -r id; do
    if [[ -n "$from" && "$id" == "$from" ]]; then
      on=1
      seen_from=1
    fi
    [[ $on -eq 1 ]] && echo "$id"
    if [[ -n "$to" && "$id" == "$to" ]]; then
      seen_to=1
      on=0
    fi
  done < <(task_ids "$track")
  [[ -z "$from" || $seen_from -eq 1 ]] || die 2 "selftest: --from $from not found"
  [[ -z "$to" || $seen_to -eq 1 ]] || die 2 "selftest: --to $to not found"
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
  local id=$1 work=$2 d prev="" b a brc=0 arc=0 note="" n
  local -a replay=()
  d="$(task_dir "$id")"
  if ! grep -Eq '^[[:space:]]*check_code[[:space:]]' "$d/checks.sh"; then
    printf '%-10s %-8s %-8s %s\n' "$id" "n/a" "n/a" "no check_code"
    return 0
  fi
  mapfile -t replay < <(_replay_ids "$id")
  n=${#replay[@]}
  [[ $n -ge 2 ]] && prev="${replay[n - 2]}"

  b="$work/before"
  if [[ -n "$prev" ]]; then
    (build_reference "$prev" "$b") || return 1
  else
    mkdir -p "$b/live"
  fi
  _selftest_grade "$id" "$b/live" "$b/modules" "$work/before.log" || brc=$?

  a="$work/after"
  (build_reference "$id" "$a") || return 1
  _selftest_grade "$id" "$a/live" "$a/modules" "$work/after.log" || arc=$?

  [[ $brc -eq 0 ]] && note="a check passes before the task"
  [[ $arc -ne 0 ]] && note="${note:+$note; }a check fails after the task"
  printf '%-10s %-8s %-8s %s
' "$id" "$([[ $brc -ne 0 ]] && echo fail || echo PASS)"     "$([[ $arc -eq 0 ]] && echo pass || echo FAIL)" "${note:-ok}"
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
  while IFS= read -r id; do
    count=$((count + 1))
    _selftest_offline_one "$id" "$work" || bad=$((bad + 1))
  done < <(_selftest_ids "$track" "$from" "$to")
  [[ $count -gt 0 ]] || die 1 "selftest: no tasks selected"
  if [[ $bad -gt 0 ]]; then
    echo "selftest offline: $bad of $count task(s) violate the contract" >&2
    return 1
  fi
  echo "selftest offline: $count task(s) ok"
}

_selftest_live() {
  local track=$1 from=$2 to=$3 id d rc
  [[ "${SELFTEST_I_HAVE_PERMISSION:-}" == 1 ]] ||
    die 8 "live selftest creates real Azure resources and costs money; set SELFTEST_I_HAVE_PERMISSION=1 to run it"
  load_config
  need az gh terraform git timeout
  while IFS= read -r id; do
    d="$(task_dir "$id")"
    echo "== $id: setup"
    if [[ -f "$d/setup.sh" ]]; then
      bash "$d/setup.sh" || die 1 "selftest: setup of $id failed"
    fi
    rc=0
    grade_quiet "$id" || rc=$?
    [[ $rc -eq 1 ]] || die 1 "selftest: $id: grade before catchup should fail (status $rc)"
    echo "== $id: fails before (ok), catchup"
    _catchup "$id" 1
    GRADE_TMP="$(mktemp -d)"
    if ! grade_task "$id" normal; then
      rm -rf "$GRADE_TMP"
      die 1 "selftest: $id: grade after catchup should pass ($GRADE_PASSED/$GRADE_TOTAL)"
    fi
    rm -rf "$GRADE_TMP"
    echo "== $id: ok"
  done < <(_selftest_ids "$track" "$from" "$to")
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
