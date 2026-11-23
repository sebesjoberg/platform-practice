# shellcheck shell=bash
# Catchup engine: ./lab.sh catchup [--yes] <id>

# _replay_ids <id>: task ids to replay, one per line, in order.
# terraform track: up to <id>.
# ansible track: terraform up to tf-25, then ansible up to <id>.
# any other track (capstone): the full terraform and ansible tracks, then that track up to <id>.
_replay_ids() {
  local id=$1 track tid t
  local -a tracks=()
  track="$(task_track "$id")"
  case "$track" in
    terraform) tracks=(terraform) ;;
    ansible)
      while IFS= read -r tid; do
        echo "$tid"
        [[ "$tid" == tf-25 ]] && break
      done < <(task_ids terraform)
      tracks=(ansible)
      ;;
    *)
      [[ -d "$TRACKS_DIR/terraform" ]] && tracks+=(terraform)
      [[ -d "$TRACKS_DIR/ansible" ]] && tracks+=(ansible)
      tracks+=("$track")
      ;;
  esac
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

_have_repo() { # _have_repo <dir>: a git repo with an origin remote
  [[ -d "$1/.git" ]] && git -C "$1" remote get-url origin >/dev/null 2>&1
}

# _require_repo <dir> <what> <creating task>
_require_repo() {
  _have_repo "$1" ||
    die 6 "$1 is not a git repo with an origin remote; the $2 repo is created in $3, do that task first"
}

VERIFIED_SHA=""

# _require_ready <dir>: exit 6 unless clean, on main, and local main contains origin/main.
# Fetches first; sets VERIFIED_SHA to the origin/main commit that was verified (empty if none).
_require_ready() {
  local dir=$1 branch
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || die 6 "uncommitted changes in $dir — commit or stash first"
  branch="$(git -C "$dir" symbolic-ref --short -q HEAD || true)"
  [[ "$branch" == main ]] || die 6 "switch to main first (currently on ${branch:-a detached HEAD}) in $dir"
  git -C "$dir" rev-parse --verify -q refs/heads/main >/dev/null || die 6 "no local main in $dir"
  git -C "$dir" fetch -q origin || die 1 "git fetch failed in $dir"
  VERIFIED_SHA=""
  if git -C "$dir" rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
    git -C "$dir" merge-base --is-ancestor refs/remotes/origin/main main ||
      die 6 "local main in $dir is behind or has diverged from origin/main — pull/merge first"
    VERIFIED_SHA="$(git -C "$dir" rev-parse refs/remotes/origin/main)"
  fi
}

# _replace_repo <dir> <refdir> <id> <scope> <yes>: scope = all | ansible
_replace_repo() {
  local dir=$1 ref=$2 id=$3 scope=$4 yes=$5 ts base n=1 reply f lease
  local -a gid=()
  _require_ready "$dir"
  lease="$VERIFIED_SHA"
  if [[ -z "$(git -C "$dir" config user.email || true)" ]]; then
    gid=(-c user.name=platform-practice -c user.email=lab@localhost)
  fi
  base="$(date +%Y%m%d-%H%M%S)"
  ts=$base
  while git -C "$dir" rev-parse --verify -q "refs/heads/my-work/$ts" >/dev/null; do
    n=$((n + 1))
    ts="$base-$n"
  done
  git -C "$dir" push -q origin "main:refs/heads/my-work/$ts" || die 1 "backup push failed in $dir"
  git -C "$dir" branch -q "my-work/$ts" main
  echo "saved your work as my-work/$ts in $(basename "$dir")"
  if [[ "$yes" -ne 1 ]]; then
    printf 'Replace main in %s with the reference state of %s? [y/N] ' "$(basename "$dir")" "$id" >&2
    reply=""
    read -r reply || true
    [[ "$reply" == y || "$reply" == Y ]] || die 6 "aborted; nothing replaced (backup is my-work/$ts)"
  fi
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
  git -C "$dir" push -q "--force-with-lease=main:$lease" origin main ||
    die 1 "push of main failed in $dir (origin/main moved since it was verified?)"
}

_run_hook() { # _run_hook <id> <phase>
  local d
  d="$(task_dir "$1")"
  [[ -f "$d/catchup.sh" ]] || return 0
  mkdir -p "$LIVE_DIR"
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
  local id=$1 yes=$2 scope=all tid out do_mod=0 rc kind need_live=0 need_mod=0
  local -a ids=()
  if [[ "$(task_track "$id")" == ansible ]]; then
    task_dir tf-25 >/dev/null || die 2 "tf-25 not found"
    rc=0
    grade_quiet tf-25 || rc=$?
    case "$rc" in
      0) ;;
      1)
        echo "tf-25 checks fail; replaying the Terraform reference first"
        _catchup tf-25 "$yes"
        ;;
      *) die "$rc" "cannot check tf-25 state (az/gh login?) — not replaying terraform" ;;
    esac
    scope=ansible
  fi
  while IFS= read -r tid; do
    [[ "$scope" == ansible && "$(task_track "$tid")" == terraform ]] && continue
    ids+=("$tid")
  done < <(_replay_ids "$id")

  out="$(mktemp -d)"
  build_reference "$id" "$out"
  if [[ "$scope" == all && -d "$out/modules" ]]; then do_mod=1; fi

  if [[ "$scope" == all ]]; then
    _have_repo "$LIVE_DIR" || need_live=1
    if [[ $do_mod -eq 1 ]]; then _have_repo "$MODULES_DIR" || need_mod=1; fi
    for tid in "${ids[@]}"; do
      kind="$(task_meta "$tid" catchup_creates_repo)"
      [[ -n "$kind" && "$kind" != false ]] || continue
      if [[ "$kind" == modules ]]; then
        [[ $need_mod -eq 1 ]] || continue
      else
        [[ $need_live -eq 1 ]] || continue
      fi
      _run_hook "$tid" before-replace
    done
  fi

  _require_repo "$LIVE_DIR" live tf-01
  _require_ready "$LIVE_DIR"
  if [[ $do_mod -eq 1 ]]; then
    _require_repo "$MODULES_DIR" modules tf-19
    _require_ready "$MODULES_DIR"
  fi

  _replace_repo "$LIVE_DIR" "$out/live" "$id" "$scope" "$yes"
  if [[ $do_mod -eq 1 ]]; then _replace_repo "$MODULES_DIR" "$out/modules" "$id" all "$yes"; fi
  rm -rf "$out"

  for tid in "${ids[@]}"; do
    kind="$(task_meta "$tid" catchup_creates_repo)"
    [[ -n "$kind" && "$kind" != false ]] && continue
    _run_hook "$tid" after-push
  done
  echo "caught up to $id"
}
