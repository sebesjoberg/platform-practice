# shellcheck shell=bash
# Catchup engine: ./lab.sh catchup [--yes] <id>
# Needs lib/progress.sh too (lab.sh sources it): a successful catchup marks the replayed tasks done.

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

# replay_into <out> <ids...>: overlay the references of the given tasks, in order, from an empty tree.
replay_into() {
  local out=$1 tid d
  shift
  rm -rf "$out"
  mkdir -p "$out/live"
  for tid in "$@"; do
    d="$(task_dir "$tid")/reference"
    [[ -d "$d" ]] || continue
    render_tree "$d/live" "$out/live"
    if [[ -d "$d/modules" ]]; then
      mkdir -p "$out/modules"
      render_tree "$d/modules" "$out/modules"
    fi
    _apply_delete "$d/.delete" "$out"
  done
}

# build_reference <id> <out>: replay overlays from an empty tree into <out>/live and <out>/modules.
build_reference() {
  local id=$1 out=$2
  local -a ids=()
  task_dir "$id" >/dev/null || die 2 "unknown task: $id"
  mapfile -t ids < <(_replay_ids "$id")
  replay_into "$out" "${ids[@]}"
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

# _ansible_path <path>: the path (relative to the repo root) is part of the Ansible track:
# ansible/ and the Ansible workflows .github/workflows/ansible*.yml.
_ansible_path() {
  case "$1" in
    ansible | ansible/*) return 0 ;;
    .github/workflows/ansible*.yml) [[ "${1#.github/workflows/}" != */* ]] ;;
    *) return 1 ;;
  esac
}

# _in_scope <scope> <path>: catchup with that scope replaces the path. all: everything (cap-01,
# the modules repo); ansible: the Ansible track only; terraform: everything but the Ansible track,
# so a learner who interleaves the tracks keeps their Ansible work.
_in_scope() {
  case "$1" in
    all) return 0 ;;
    ansible) _ansible_path "$2" ;;
    terraform) ! _ansible_path "$2" ;;
    *) return 1 ;;
  esac
}

# _ref_list <refdir> <scope> <out>: the reference files in scope, NUL-separated relative paths.
_ref_list() {
  local ref=$1 scope=$2 out=$3 p
  : >"$out"
  [[ -d "$ref" ]] || return 0
  while IFS= read -r -d '' p; do
    p=${p#./}
    if _in_scope "$scope" "$p"; then printf '%s\0' "$p" >>"$out"; fi
  done < <(cd "$ref" && find . -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)
  return 0
}

# _ignored_entries <dir> <path>: the paths a rule ignores, NUL-separated: <path> itself (a file, or
# a directory a rule names, like ansible/.venv/), or, for a directory git only lists because
# everything in it is ignored (ansible/ holding just .venv and .facts), what is ignored inside it.
# Never such a directory itself: new files the learner adds there must not be ignored.
_ignored_entries() {
  local dir=$1 p=$2 c
  if [[ "$p" != */ ]] || git -C "$dir" check-ignore -q -- "$p"; then
    printf '%s\0' "$p"
    return 0
  fi
  while IFS= read -r -d '' c; do
    c=${c#"$dir/"}
    if [[ -d "$dir/$c" && ! -L "$dir/$c" ]]; then c+=/; fi
    _ignored_entries "$dir" "$c"
  done < <(find "$dir/$p" -mindepth 1 -maxdepth 1 -print0)
  return 0
}

# _keep_ignored <dir>: what the learner's .gitignore files ignore right now (a .env, ansible/.venv,
# fact caches...) stays ignored once catchup has swapped those files for the reference ones: the
# ignored paths go to .git/info/exclude, anchored and glob-escaped. They stay on disk and are
# never staged.
_keep_ignored() {
  local dir=$1 ex p e
  local -a add=()
  while IFS= read -r -d '' e; do
    while IFS= read -r -d '' p; do
      p="/$(printf '%s' "$p" | sed 's/[][*?\]/\\&/g')"
      add+=("$p")
    done < <(_ignored_entries "$dir" "$e")
  done < <(git -C "$dir" ls-files -z -o -i --exclude-standard --directory)
  [[ ${#add[@]} -gt 0 ]] || return 0
  ex="$(git -C "$dir" rev-parse --git-path info/exclude)"
  [[ "$ex" == /* ]] || ex="$dir/$ex"
  mkdir -p "$(dirname "$ex")"
  touch "$ex"
  grep -qxF '# kept ignored by ./lab.sh catchup' "$ex" || echo '# kept ignored by ./lab.sh catchup' >>"$ex"
  for p in "${add[@]}"; do
    grep -qxF -- "$p" "$ex" || printf '%s\n' "$p" >>"$ex"
  done
}

BACKUP_BRANCH=""

# _backup_repo <dir>: save main as my-work/<timestamp> on origin and locally. Sets BACKUP_BRANCH
# and VERIFIED_SHA (the lease for the push that replaces main).
_backup_repo() {
  local dir=$1 ts base n=1
  _require_ready "$dir"
  base="$(date +%Y%m%d-%H%M%S)"
  ts=$base
  while git -C "$dir" rev-parse --verify -q "refs/heads/my-work/$ts" >/dev/null; do
    n=$((n + 1))
    ts="$base-$n"
  done
  git -C "$dir" push -q origin "main:refs/heads/my-work/$ts" || die 1 "backup push failed in $dir"
  git -C "$dir" branch -q "my-work/$ts" main
  BACKUP_BRANCH="my-work/$ts"
  echo "saved your work as my-work/$ts in $(basename "$dir")"
}

# _replace_repo <dir> <refdir> <id> <scope> <lease>: scope = all | terraform | ansible (see
# _in_scope). Replaces those paths of main with the reference, commits, and pushes main with a
# lease on the origin/main commit _backup_repo verified. Only the reference's own files are
# staged: files the learner's .gitignore ignored never reach the (public) repo.
_replace_repo() {
  local dir=$1 ref=$2 id=$3 scope=$4 lease=$5 list
  local -a gid=()
  if [[ -z "$(git -C "$dir" config user.email || true)" ]]; then
    gid=(-c user.name=platform-practice -c user.email=lab@localhost)
  fi
  _keep_ignored "$dir"
  case "$scope" in
    all) git -C "$dir" rm -rfq --ignore-unmatch -- . ;;
    ansible) git -C "$dir" rm -rfq --ignore-unmatch -- ansible ':(glob).github/workflows/ansible*.yml' ;;
    terraform)
      git -C "$dir" rm -rfq --ignore-unmatch -- . ':(exclude)ansible' ':(exclude,glob).github/workflows/ansible*.yml'
      ;;
    *) die 2 "unknown catchup scope $scope" ;;
  esac
  list="$(mktemp)"
  _ref_list "$ref" "$scope" "$list"
  if [[ -s "$list" ]]; then
    (cd "$ref" && tar --null -T "$list" -cf -) | tar -C "$dir" -xpf - || die 1 "could not copy the reference into $dir"
    git -C "$dir" --literal-pathspecs add -f --pathspec-from-file="$list" --pathspec-file-nul
  fi
  rm -f "$list"
  if ! git -C "$dir" diff --cached --quiet; then
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
  # CATCHUP_YES=1 (catchup --yes) tells hooks not to ask (tf-19/tf-20 before moving a release tag).
  (cd "$LIVE_DIR" && CATCHUP_PHASE=$2 CATCHUP_YES="${CATCHUP_YES:-0}" bash "$d/catchup.sh") || die 1 "catchup.sh of $1 failed"
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
  require_not_paused
  need git
  task_dir "$id" >/dev/null || die 2 "unknown task: $id"
  _catchup "$id" "$yes"
}

# _tf_past_25: why the learner's Terraform work is past tf-25, empty when it isn't: a started or
# finished tf-26+ task, a stack only tf-29/tf-31 create, or a paused lab (whose checks fail anyway).
_tf_past_25() {
  local t s
  t="$(awk -F'\t' '$1 ~ /^tf-[0-9]+$/ && $2 != "" && substr($1, 4) + 0 > 25 { print $1; exit }' \
    "$(progress_file)" 2>/dev/null || true)"
  if [[ -n "$t" ]]; then
    if progress_done "$t"; then echo "$t is done"; else echo "$t is started"; fi
    return 0
  fi
  for s in observability teams; do
    if [[ -d "$LIVE_DIR/terraform/$s" ]]; then
      echo "terraform/$s exists in $LIVE_DIR"
      return 0
    fi
  done
  if [[ -e "$LAB_HOME/paused" ]]; then echo "the lab is paused"; fi
  return 0
}

# _print_failed <grade log>: the failing checks of a grade run and their reasons.
_print_failed() {
  awk '/FAIL/ { print; f = 1; next } f && /^    / { print; next } { f = 0 }' "$1"
}

# _tf25_baseline <ansible id>: before an Ansible catchup, check tf-25's state. Its checks pass:
# tf-25 counts as done (as good as ./lab.sh grade tf-25, which every Ansible task requires).
# Some fail: replay the Terraform reference up to tf-25, unless the learner's Terraform is past
# tf-25 — catchup an-XX never rolls back later Terraform work; it stops and prints the failing
# checks instead. Can't grade (not logged in, checks.sh doesn't load): stop, replay nothing.
_tf25_baseline() {
  local id=$1 yes=$2 log rc=0 why
  task_dir tf-25 >/dev/null || die 2 "tf-25 not found"
  log="$(mktemp)"
  grade_capture tf-25 "$log" || rc=$?
  case "$rc" in
    0) TF25_DONE=1 ;;
    1)
      if ! grep -q 'FAIL' "$log"; then
        cat "$log" >&2
        rm -f "$log"
        die 1 "cannot grade tf-25 (see above) — not replaying terraform"
      fi
      why="$(_tf_past_25)"
      if [[ -n "$why" ]]; then
        echo "tf-25 checks fail:" >&2
        _print_failed "$log" >&2
        rm -f "$log"
        die 6 "not replaying the tf-25 reference: your Terraform work is past tf-25 ($why), and catchup $id never rolls it back. Fix the failing tf-25 checks above (a paused lab: ./lab.sh resume; a new IP: ./lab.sh init --refresh-ip; a red run on main: fix it), then ./lab.sh catchup $id again"
      fi
      rm -f "$log"
      echo "tf-25 checks fail; replaying the Terraform reference first"
      _catchup tf-25 "$yes"
      ;;
    *)
      rm -f "$log"
      die "$rc" "cannot check tf-25 state (az/gh login?) — not replaying terraform"
      ;;
  esac
}

_catchup() {
  local id=$1 yes=$2 scope tid out do_mod=0 kind need_live=0 need_mod=0 reply
  local live_lease mod_lease="" backups
  # shellcheck disable=SC2034 # read by _run_hook (dynamic scope)
  local CATCHUP_YES=$yes TF25_DONE=0
  local -a ids=() done_ids=()
  case "$(task_track "$id")" in
    terraform) scope=terraform ;;
    ansible)
      scope=ansible
      _tf25_baseline "$id" "$yes"
      [[ $TF25_DONE -eq 1 ]] && done_ids+=(tf-25)
      ;;
    *) scope=all ;;
  esac
  while IFS= read -r tid; do
    [[ "$scope" == ansible && "$(task_track "$tid")" == terraform ]] && continue
    ids+=("$tid")
  done < <(_replay_ids "$id")

  out="$(mktemp -d)"
  build_reference "$id" "$out"
  if [[ "$scope" != ansible && -d "$out/modules" ]]; then do_mod=1; fi

  if [[ "$scope" != ansible ]]; then
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

  # Back up every repo first, then ask once for all of them, then replace: declining replaces
  # nothing.
  _backup_repo "$LIVE_DIR"
  live_lease=$VERIFIED_SHA
  backups="$BACKUP_BRANCH in $(basename "$LIVE_DIR")"
  if [[ $do_mod -eq 1 ]]; then
    _backup_repo "$MODULES_DIR"
    mod_lease=$VERIFIED_SHA
    backups+=", $BACKUP_BRANCH in $(basename "$MODULES_DIR")"
  fi
  if [[ "$yes" -ne 1 ]]; then
    if [[ $do_mod -eq 1 ]]; then
      printf 'Replace main in %s and %s with the reference state of %s? [y/N] ' \
        "$(basename "$LIVE_DIR")" "$(basename "$MODULES_DIR")" "$id" >&2
    else
      printf 'Replace main in %s with the reference state of %s? [y/N] ' "$(basename "$LIVE_DIR")" "$id" >&2
    fi
    reply=""
    read -r reply || true
    [[ "$reply" == y || "$reply" == Y ]] || die 6 "aborted; nothing replaced (backup: $backups)"
  fi

  _replace_repo "$LIVE_DIR" "$out/live" "$id" "$scope" "$live_lease"
  if [[ $do_mod -eq 1 ]]; then _replace_repo "$MODULES_DIR" "$out/modules" "$id" all "$mod_lease"; fi
  rm -rf "$out"

  # Every replayed task's hook runs after the push, repo-creating ones too (tf-19 tags its
  # release then); their scripts tell the phases apart with CATCHUP_PHASE.
  for tid in "${ids[@]}"; do
    _run_hook "$tid" after-push
  done
  # Every replayed task is done now, as if graded: ./lab.sh next continues after <id> and
  # grade --all covers them. Start times already recorded are kept.
  for tid in "${done_ids[@]}" "${ids[@]}"; do
    progress_finish "$tid"
  done
  echo "caught up to $id"
}
