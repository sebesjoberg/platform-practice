# shellcheck shell=bash
# Task lookup over $TRACKS_DIR/<track>/NN-slug/

# fm_get <file> <key>: value of a front matter key.
fm_get() {
  awk -v k="$2" '
    { sub(/\r$/, "") }
    NR==1 && $0!="---" {exit}
    NR>1 && $0=="---" {exit}
    NR>1 { i=index($0, ":"); if (i && substr($0,1,i-1)==k) { v=substr($0,i+1); sub(/^[ \t]+/,"",v); sub(/\r$/,"",v); print v; exit } }
  ' "$1"
}

list_tracks() {
  local d
  for d in "$TRACKS_DIR"/*/; do
    [[ -d "$d" ]] && basename "$d"
  done
  return 0
}

# task_ids [track]: ids in directory order (all tracks when none is given).
task_ids() {
  local track="${1:-*}" f
  # shellcheck disable=SC2231 # track may be the * wildcard
  for f in "$TRACKS_DIR"/$track/*/task.md; do
    [[ -f "$f" ]] && fm_get "$f" id
  done
  return 0
}

task_dir() {
  local f
  for f in "$TRACKS_DIR"/*/*/task.md; do
    [[ -f "$f" ]] || continue
    if [[ "$(fm_get "$f" id)" == "$1" ]]; then
      dirname "$f"
      return 0
    fi
  done
  return 1
}

task_meta() { # task_meta <id> <key>
  local d
  d="$(task_dir "$1")" || return 1
  fm_get "$d/task.md" "$2"
}

task_track() {
  basename "$(dirname "$(task_dir "$1")")"
}

# task_requires <id>: one required id per line.
task_requires() {
  task_meta "$1" requires | tr -d '[],' | tr -s ' ' '\n' | sed '/^$/d'
}

# print_body <file>: a markdown file without its front matter.
print_body() {
  awk '{ sub(/\r$/, "") } NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$1"
}

# show_md <file>: print_body, with template tokens rendered from the learner's config when one
# exists (unrendered otherwise). Needs lib/config.sh and lib/template.sh.
show_md() {
  if [[ -f "$LAB_HOME/config.env" ]]; then
    (
      load_config
      print_body "$1" | render_text
    )
  else
    print_body "$1"
  fi
}

resolve_id() { # resolve_id [id]: the given id or the current task
  local id="${1:-$(current_task)}"
  [[ -n "$id" ]] || die 1 "no current task; run ./lab.sh next"
  task_dir "$id" >/dev/null || die 1 "unknown task: $id"
  echo "$id"
}

cmd_show() { # cmd_show <file> [id]
  local file=$1 id d
  id="$(resolve_id "${2:-}")"
  d="$(task_dir "$id")"
  [[ -f "$d/$file" ]] || die 1 "$id has no $file"
  show_md "$d/$file"
}

cmd_next() {
  local track="${1:-}" id req d cur
  require_not_paused
  if [[ -z "$track" ]]; then
    cur="$(current_task)"
    if [[ -n "$cur" ]] && task_dir "$cur" >/dev/null; then track="$(task_track "$cur")"; else track=terraform; fi
  fi
  [[ -d "$TRACKS_DIR/$track" ]] || die 1 "unknown track: $track"
  while IFS= read -r id; do
    progress_done "$id" && continue
    for req in $(task_requires "$id"); do
      progress_done "$req" || die 1 "finish $req first or ./lab.sh catchup $id"
    done
    d="$(task_dir "$id")"
    if [[ -f "$d/setup.sh" ]]; then
      bash "$d/setup.sh" || die 1 "setup for $id failed"
    fi
    show_md "$d/task.md"
    progress_start "$id"
    return 0
  done < <(task_ids "$track")
  echo "all tasks in $track done"
}

cmd_status() {
  local track id title state
  for track in $(list_tracks); do
    echo "== $track"
    printf '%-10s %-40s %s\n' id title 'done'
    while IFS= read -r id; do
      title="$(task_meta "$id" title)"
      if progress_done "$id"; then state='done'; else state='-'; fi
      printf '%-10s %-40s %s\n' "$id" "$title" "$state"
    done < <(task_ids "$track")
  done
}
