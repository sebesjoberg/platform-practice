# shellcheck shell=bash
# Catchup engine: ./lab.sh catchup [--yes] <id>

# _replay_ids <id>: task ids to replay, one per line, in order.
# tf-*: the terraform track up to <id>. Any other track: terraform up to tf-25, then
# (when <id> is not in the ansible track) all of ansible, then the id's own track up to <id>.
_replay_ids() {
  local id=$1 track tid t
  local -a tracks
  track="$(task_track "$id")"
  if [[ "$track" == terraform ]]; then
    while IFS= read -r tid; do
      echo "$tid"
      [[ "$tid" == "$id" ]] && return 0
    done < <(task_ids terraform)
    return 0
  fi
  while IFS= read -r tid; do
    echo "$tid"
    [[ "$tid" == tf-25 ]] && break
  done < <(task_ids terraform)
  tracks=()
  [[ "$track" != ansible && -d "$TRACKS_DIR/ansible" ]] && tracks+=(ansible)
  tracks+=("$track")
  for t in "${tracks[@]}"; do
    while IFS= read -r tid; do
      echo "$tid"
      [[ "$tid" == "$id" ]] && return 0
    done < <(task_ids "$t")
  done
  return 0
}

# _apply_delete <list> <out>: remove the listed paths (relative to <out>).
_apply_delete() {
  local list=$1 out=$2 p
  [[ -f "$list" ]] || return 0
  while IFS= read -r p || [[ -n "$p" ]]; do
    p="${p%$'\r'}"
    [[ -n "$p" && "$p" != \#* ]] || continue
    [[ "$p" != /* && "$p" != *..* ]] || die 5 "unsafe path in $list: $p"
    rm -rf "${out:?}/$p"
  done <"$list"
}

# build_reference <id> <out>: replay overlays from an empty tree into <out>/live and <out>/modules.
build_reference() {
  local id=$1 out=$2 tid d
  task_dir "$id" >/dev/null || die 2 "unknown task: $id"
  rm -rf "$out"
  mkdir -p "$out/live"
  while IFS= read -r tid; do
    d="$(task_dir "$tid")/reference"
    [[ -d "$d" ]] || continue
    render_tree "$d/live" "$out/live"
    if [[ -d "$d/modules" ]]; then
      mkdir -p "$out/modules"
      render_tree "$d/modules" "$out/modules"
    fi
    _apply_delete "$d/.delete" "$out"
  done < <(_replay_ids "$id")
}

# _require_repo <dir> <what> <creating task>: exit 6 unless <dir> is a git repo with an origin.
_require_repo() {
  local dir=$1 what=$2 task=$3
  if [[ ! -d "$dir/.git" ]] || ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    die 6 "$dir is not a git repo with an origin remote; the $what repo is created in $task, do that task first"
  fi
}

_require_clean() {
  [[ -z "$(git -C "$1" status --porcelain)" ]] || die 6 "uncommitted changes in $1 — commit or stash first"
}

# _replace_repo <dir> <refdir> <id> <scope> <yes>: scope = all | ansible
_replace_repo() {
  local dir=$1 ref=$2 id=$3 scope=$4 yes=$5 ts reply f
  local -a gid=()
  if [[ -z "$(git -C "$dir" config user.email || true)" ]]; then
    gid=(-c user.name=platform-practice -c user.email=lab@localhost)
  fi
  ts="$(date +%Y%m%d-%H%M%S)"
  if git -C "$dir" rev-parse --verify -q main >/dev/null; then
    git -C "$dir" push -q origin "main:refs/heads/my-work/$ts" || die 1 "backup push failed in $dir"
    git -C "$dir" branch -q -f "my-work/$ts" main
    echo "saved your work as my-work/$ts in $(basename "$dir")"
  fi
  if [[ "$yes" -ne 1 ]]; then
    printf 'Replace main in %s with the reference state of %s? [y/N] ' "$(basename "$dir")" "$id" >&2
    reply=""
    read -r reply || true
    [[ "$reply" == y || "$reply" == Y ]] || die 6 "aborted; nothing replaced (backup is my-work/$ts)"
  fi
  git -C "$dir" checkout -q -B main
  if [[ "$scope" == ansible ]]; then
    git -C "$dir" rm -rfq --ignore-unmatch -- ansible ':(glob).github/workflows/ansible*.yml'
    if [[ -d "$ref/ansible" ]]; then
      mkdir -p "$dir/ansible"
      cp -a "$ref/ansible/." "$dir/ansible/"
    fi
    for f in "$ref"/.github/workflows/ansible*.yml; do
      [[ -f "$f" ]] || continue
      mkdir -p "$dir/.github/workflows"
      cp -a "$f" "$dir/.github/workflows/"
    done
  else
    git -C "$dir" rm -rfq --ignore-unmatch -- .
    cp -a "$ref/." "$dir/"
  fi
  git -C "$dir" add -A
  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    git -C "$dir" "${gid[@]}" commit -q -m "catchup: $id"
  fi
  git -C "$dir" push -q --force-with-lease origin main || die 1 "push of main failed in $dir"
}

_run_hook() { # _run_hook <id> <phase>
  local d
  d="$(task_dir "$1")"
  [[ -f "$d/catchup.sh" ]] || return 0
  (cd "$LIVE_DIR" && CATCHUP_PHASE=$2 bash "$d/catchup.sh") || die 1 "catchup.sh of $1 failed"
}

cmd_catchup() {
  local yes=0 id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes | -y) yes=1 ;;
      -*) die 2 "catchup: unknown option $1" ;;
      *) id=$1 ;;
    esac
    shift
  done
  [[ -n "$id" ]] || die 2 "usage: ./lab.sh catchup [--yes] <id>"
  load_config
  need git
  task_dir "$id" >/dev/null || die 2 "unknown task: $id"
  _catchup "$id" "$yes"
}

_catchup() {
  local id=$1 yes=$2 scope=all tid out do_mod=0
  local -a ids=()
  if [[ "$(task_track "$id")" != terraform ]]; then
    task_dir tf-25 >/dev/null || die 2 "tf-25 not found"
    if grade_quiet tf-25; then
      scope=ansible
    else
      echo "tf-25 checks fail; replaying the Terraform reference first"
      _catchup tf-25 "$yes"
    fi
  fi
  while IFS= read -r tid; do
    [[ "$scope" == ansible && "$(task_track "$tid")" == terraform ]] && continue
    ids+=("$tid")
  done < <(_replay_ids "$id")

  out="$(mktemp -d)"
  build_reference "$id" "$out"

  for tid in "${ids[@]}"; do
    [[ "$(task_meta "$tid" catchup_creates_repo)" == true ]] || continue
    mkdir -p "$LIVE_DIR"
    _run_hook "$tid" before-replace
  done

  _require_repo "$LIVE_DIR" live tf-01
  _require_clean "$LIVE_DIR"
  if [[ "$scope" == all && -d "$out/modules" ]]; then
    do_mod=1
    _require_repo "$MODULES_DIR" modules tf-19
    _require_clean "$MODULES_DIR"
  fi

  _replace_repo "$LIVE_DIR" "$out/live" "$id" "$scope" "$yes"
  if [[ $do_mod -eq 1 ]]; then _replace_repo "$MODULES_DIR" "$out/modules" "$id" all "$yes"; fi
  rm -rf "$out"

  for tid in "${ids[@]}"; do
    [[ "$(task_meta "$tid" catchup_creates_repo)" == true ]] && continue
    _run_hook "$tid" after-push
  done
  echo "caught up to $id"
}
