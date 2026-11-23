#!/usr/bin/env bash
# Lint the lab content: tests/lint-tracks.sh [track]
# Honours TRACKS_DIR (default <repo>/tracks). Prints `<task-dir>: <problem>` per violation, exit 1 if any.
#
# Escape hatches (on the offending line): `lint-allow: banned`, `lint-allow: naming`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACKS_DIR="${TRACKS_DIR:-$REPO/tracks}"
# shellcheck source=lib/common.sh
source "$REPO/lib/common.sh"
# shellcheck source=lib/template.sh
source "$REPO/lib/template.sh"
# shellcheck source=lib/tasks.sh
source "$REPO/lib/tasks.sh"

# ---------------------------------------------------------------------------------------
# Naming table (constraints.md). Extend here when content needs a new resource kind.
# Every backticked, resource-like name in task.md must fully match one of these ERE patterns.
# Placeholders: @P@ = PREFIX ([a-z]{2,6}, or {P} / {{PREFIX}}), @S@ = SUFFIX ([a-z0-9]{6},
# or {S} / {{SUFFIX}}), @E@ = environment (dev|prod|{env}), @V@ = vnet short name.
# ---------------------------------------------------------------------------------------
NAMING_PATTERNS=(
  '^rg-@P@-(tfstate|hub|@E@|shared|legacy|payments)$'
  '^st@P@(tfstate|legacy)@S@$'
  '^id-@P@-(github-ci|app-@E@|payments-ci)$'
  '^vnet-@P@-@V@$'
  '^snet-(shared|runner|pe|app|aca)$'
  '^nsg-@P@-@V@-(shared|runner|pe|app|aca)$'
  '^peer-(hub-to-@E@|@E@-to-hub)$'
  '^law-@P@-platform$'
  '^acr@P@@S@$'
  '^kv-@P@-@E@-@S@$'
  '^cae-@P@-@E@$'
  '^ca-@P@-hello-@E@$'
  '^pe-kv-@P@-@E@$'
  '^vm-@P@-(jump|web-dev-[12])$'
  '^pip-@P@-jump$'
  '^ag-@P@-budget$'
  '^budget-@P@-(monthly|payments)$'
)
# Banned SKU/service strings (reference/ files, task.md, solution.md).
BANNED=(AzureFirewall Bastion VpnGw Premium azurerm_kubernetes_cluster azuread_)
# ---------------------------------------------------------------------------------------

P_RE='([a-z]{2,6}|\{P\}|\{\{PREFIX\}\})'
S_RE='([a-z0-9]{6}|\{S\}|\{\{SUFFIX\}\})'
E_RE='(dev|prod|\{env\})'
V_RE='(hub|dev|prod)'
EXPANDED=()
for pat in "${NAMING_PATTERNS[@]}"; do
  pat="${pat//@P@/$P_RE}"
  pat="${pat//@S@/$S_RE}"
  pat="${pat//@E@/$E_RE}"
  pat="${pat//@V@/$V_RE}"
  EXPANDED+=("$pat")
done

# Candidate resource names inside backticks: hyphenated prefixes, or st/acr names that contain
# a placeholder or are long enough not to be an ordinary word.
CAND_RE='(?<![A-Za-z0-9_-])((rg|vnet|snet|nsg|peer|id|kv|cae|ca|pe|pip|vm|law|ag|budget)-[A-Za-z0-9{}_-]*|(st|acr)[a-z0-9]*\{[A-Za-z0-9{}_-]*|(st|acr)[a-z0-9]{10,})'

BACKTICK_RE="\`[^\`]+\`"
VIOLATIONS=0
violation() { # violation <task-dir> <text>
  printf '%s: %s\n' "$(basename "$1")" "$2"
  VIOLATIONS=$((VIOLATIONS + 1))
}

command -v shellcheck >/dev/null || die 3 "shellcheck is required (scripts/install-dev-tools.sh)"

ALL_IDS=" $(task_ids | tr '\n' ' ') "

lint_task() {
  local d=$1 f id key val req n rel tok line out
  # required files
  for f in task.md hint.md solution.md checks.sh; do
    [[ -f "$d/$f" ]] || violation "$d" "missing $f"
  done
  # front matter
  if [[ -f "$d/task.md" ]]; then
    for key in id title target_minutes requires; do
      val="$(fm_get "$d/task.md" "$key")"
      if [[ -z "$val" ]]; then
        violation "$d" "front matter key $key missing"
      fi
    done
    val="$(fm_get "$d/task.md" target_minutes)"
    [[ -z "$val" || "$val" =~ ^[0-9]+$ ]] || violation "$d" "front matter target_minutes is not a number: $val"
    val="$(fm_get "$d/task.md" requires)"
    if [[ -n "$val" ]]; then
      [[ "$val" =~ ^\[[A-Za-z0-9,\ -]*\]$ ]] || violation "$d" "front matter requires is not a [list]: $val"
      for req in $(tr -d '[],' <<<"$val"); do
        [[ "$ALL_IDS" == *" $req "* ]] || violation "$d" "requires unknown id $req"
      done
    fi
    id="$(fm_get "$d/task.md" id)"
    if [[ -n "$id" ]]; then
      n="$(task_ids | grep -cx -- "$id" || true)"
      [[ "$n" -le 1 ]] || violation "$d" "duplicate id $id"
    fi
  fi
  # checks.sh must call check/check_code
  if [[ -f "$d/checks.sh" ]]; then
    grep -Eq '^[[:space:]]*check(_code)?[[:space:]]' "$d/checks.sh" ||
      violation "$d" "checks.sh has no check/check_code call"
  fi
  # run shellcheck on the shell scripts
  for f in checks.sh setup.sh catchup.sh; do
    [[ -f "$d/$f" ]] || continue
    if ! out="$(shellcheck -s bash -e SC2016 "$d/$f" 2>&1)"; then
      violation "$d" "shellcheck: $f"
      printf '%s\n' "$out" | sed 's/^/    /'
    fi
  done
  # CRLF in any text file
  while IFS= read -r f; do
    violation "$d" "CRLF line endings in ${f#"$d"/}"
  done < <(grep -rIl $'\r' "$d" 2>/dev/null | sort || true)
  # template tokens in reference/
  if [[ -d "$d/reference" ]]; then
    while IFS= read -r -d '' f; do
      grep -Iq . "$f" 2>/dev/null || continue
      rel="${f#"$d"/}"
      while IFS= read -r tok; do
        [[ -n "$tok" ]] || continue
        [[ " $TEMPLATE_TOKENS " == *" ${tok:2:${#tok}-4} "* ]] ||
          violation "$d" "unknown template token $tok in $rel"
      done < <(grep -oE '\{\{[A-Z_]+\}\}' "$f" | sort -u || true)
    done < <(find "$d/reference" -type f -print0 | sort -z)
  fi
  # banned strings
  local -a banned_files=()
  [[ -f "$d/task.md" ]] && banned_files+=("$d/task.md")
  [[ -f "$d/solution.md" ]] && banned_files+=("$d/solution.md")
  if [[ -d "$d/reference" ]]; then
    while IFS= read -r -d '' f; do banned_files+=("$f"); done < <(find "$d/reference" -type f -print0 | sort -z)
  fi
  for f in "${banned_files[@]}"; do
    grep -Iq . "$f" 2>/dev/null || continue
    rel="${f#"$d"/}"
    for tok in "${BANNED[@]}"; do
      if grep -v 'lint-allow: banned' "$f" | grep -qF -- "$tok"; then
        violation "$d" "banned string $tok in $rel"
      fi
    done
  done
  # resource names in task.md
  if [[ -f "$d/task.md" ]]; then
    local span name ok pat
    while IFS= read -r line; do
      [[ "$line" == *'lint-allow: naming'* ]] && continue
      while IFS= read -r span; do
        [[ -n "$span" ]] || continue
        while IFS= read -r name; do
          [[ -n "$name" ]] || continue
          ok=0
          for pat in "${EXPANDED[@]}"; do
            if [[ "$name" =~ $pat ]]; then ok=1; break; fi
          done
          [[ $ok -eq 1 ]] || violation "$d" "resource name $name in task.md does not match the naming table"
        done < <(grep -oP "$CAND_RE" <<<"$span" || true)
      done < <(grep -oE "$BACKTICK_RE" <<<"$line" | tr -d '`' || true)
    done < <(print_body "$d/task.md")
  fi
}

tracks=()
if [[ -n "${1:-}" ]]; then
  [[ -d "$TRACKS_DIR/$1" ]] || {
    if [[ -z "$(list_tracks)" ]]; then
      echo "no tracks"
      exit 0
    fi
    die 2 "unknown track: $1"
  }
  tracks=("$1")
else
  mapfile -t tracks < <(list_tracks)
fi
if [[ ${#tracks[@]} -eq 0 ]]; then
  echo "no tracks"
  exit 0
fi

for t in "${tracks[@]}"; do
  for d in "$TRACKS_DIR/$t"/*/; do
    [[ -d "$d" ]] || continue
    lint_task "${d%/}"
  done
done

if [[ $VIOLATIONS -gt 0 ]]; then
  echo "lint: $VIOLATIONS violation(s)" >&2
  exit 1
fi
echo "lint: ok"
