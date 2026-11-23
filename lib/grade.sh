# shellcheck shell=bash
# Grader: ./lab.sh grade [id | --all | --offline id]

# grade_preflight: once per grade invocation, lazily before the first cloud check.
grade_preflight() {
  [[ -e "$GRADE_TMP/preflight" ]] && return 0
  local sub
  sub="$(az account show --query id -o tsv 2>/dev/null | tr -d '\r')" || sub=""
  [[ -n "$sub" && "$sub" == "${SUBSCRIPTION_ID:-}" ]] ||
    die 4 "az not logged in to the lab subscription (az login; az account set -s …)"
  gh auth status >/dev/null 2>&1 || die 4 "gh not logged in (gh auth login)"
  : >"$GRADE_TMP/preflight"
}

# grade_task <id> <mode>: prints checks, sets GRADE_PASSED/GRADE_TOTAL. Returns 0 when all pass.
# mode: normal | offline
grade_task() {
  local id=$1 mode=$2 d rc=0
  d="$(task_dir "$id")"
  [[ -f "$d/checks.sh" ]] || die 1 "$id has no checks.sh"
  bash -n "$d/checks.sh" 2>/dev/null || die 1 "$id: checks.sh failed to load"
  bash -n "$d/checks.sh" 2>/dev/null || die 1 "$id: checks.sh failed to load"
  : >"$GRADE_TMP/results"
  (
    export GRADE_RESULTS="$GRADE_TMP/results" GRADE_TMP
    [[ "$mode" == offline ]] && export GRADE_OFFLINE=1
    # shellcheck disable=SC1091
    source "$LAB_ROOT/lib/checks-api.sh"
    # shellcheck disable=SC1091
    source "$d/checks.sh" || true
    exit 0
  ) </dev/null || rc=$?
  [[ $rc -eq 0 ]] || exit "$rc"
  GRADE_TOTAL="$(wc -l <"$GRADE_TMP/results" | tr -d ' ')"
  GRADE_PASSED="$(grep -c '^P$' "$GRADE_TMP/results" || true)"
  [[ "$GRADE_PASSED" -eq "$GRADE_TOTAL" ]]
}

# grade_order: finished task ids in track order (terraform, ansible, capstone, others alphabetically).
grade_order() {
  local track id
  local -a tracks=()
  for track in terraform ansible capstone; do
    [[ -d "$TRACKS_DIR/$track" ]] && tracks+=("$track")
  done
  for track in $(list_tracks); do
    case "$track" in terraform | ansible | capstone) ;; *) tracks+=("$track") ;; esac
  done
  for track in "${tracks[@]}"; do
    while IFS= read -r id; do
      progress_done "$id" && echo "$id"
    done < <(task_ids "$track")
  done
  return 0
}

cmd_grade() {
  load_config
  need timeout
  GRADE_TMP="$(mktemp -d)"
  trap 'rm -rf "$GRADE_TMP"' EXIT
  local mode=normal all=0 id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1 ;;
      --offline) mode=offline ;;
      -*) die 2 "grade: unknown option $1" ;;
      *) id=$1 ;;
    esac
    shift
  done

  if [[ $all -eq 1 ]]; then
    local regress=() tid
    while IFS= read -r tid; do
      echo "== $tid"
      if grade_task "$tid" "$mode"; then :; else regress+=("$tid"); fi
      echo "$GRADE_PASSED/$GRADE_TOTAL passed"
    done < <(grade_order)

    if [[ ${#regress[@]} -gt 0 ]]; then
      echo "regressions: ${regress[*]}"
      exit 1
    fi
    echo "no regressions"
    return 0
  fi

  if [[ -z "$id" ]]; then
    id="$(current_task)"
    [[ -n "$id" ]] || die 1 "no current task; run ./lab.sh next"
  fi
  task_dir "$id" >/dev/null || die 2 "unknown task: $id"

  local row started="" target now mins timing rc=0
  row="$(progress_row "$id")"
  [[ -n "$row" ]] && started="$(cut -f2 <<<"$row")"
  target="$(task_meta "$id" target_minutes)"
  grade_task "$id" "$mode" || rc=$?
  if [[ -n "$started" ]]; then
    now="$(date +%s)"
    mins=$(((now - started + 30) / 60))
  else
    mins="?"
  fi
  timing="took $mins min (target $target)"
  echo "$GRADE_PASSED/$GRADE_TOTAL passed — $timing"
  if [[ $rc -eq 0 ]]; then
    [[ "$mode" == offline ]] || progress_finish "$id"
    return 0
  fi
  exit 1
}
