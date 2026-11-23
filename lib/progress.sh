# shellcheck shell=bash
# Progress: $LAB_HOME/progress, TSV: id<TAB>started<TAB>finished (epoch seconds).

progress_file() { echo "$LAB_HOME/progress"; }

progress_row() { # progress_row <id>
  [[ -f "$(progress_file)" ]] || return 0
  awk -F'\t' -v id="$1" '$1==id {print; exit}' "$(progress_file)"
}

progress_start() { # keeps the original start time when already started
  mkdir -p "$LAB_HOME"
  [[ -n "$(progress_row "$1")" ]] && return 0
  printf '%s\t%s\t\n' "$1" "$(date +%s)" >>"$(progress_file)"
}

progress_finish() {
  progress_start "$1"
  local tmp="$LAB_HOME/progress.tmp"
  awk -F'\t' -v OFS='\t' -v id="$1" -v now="$(date +%s)" '$1==id && $3=="" {$3=now} {print}' \
    "$(progress_file)" >"$tmp"
  mv "$tmp" "$(progress_file)"
}

progress_done() { # exit 0 when finished
  local row finished
  row="$(progress_row "$1")"
  [[ -n "$row" ]] || return 1
  finished="$(cut -f3 <<<"$row")"
  [[ -n "$finished" ]]
}

# current_task: the last unfinished task, else the last one touched; empty if none.
current_task() {
  [[ -s "$(progress_file)" ]] || return 0
  local open
  open="$(awk -F'\t' '$3=="" {id=$1} END {print id}' "$(progress_file)")"
  if [[ -n "$open" ]]; then echo "$open"; else tail -n1 "$(progress_file)" | cut -f1; fi
}
