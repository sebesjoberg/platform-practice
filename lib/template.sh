# shellcheck shell=bash
# Templating: render_text (stdin -> stdout), render_tree <src> <dst>

TEMPLATE_TOKENS="PREFIX SUFFIX LOCATION SUBSCRIPTION_ID TENANT_ID GH_OWNER LIVE_REPO MODULES_REPO LEARNER_IP OWNER_TAG"

# _sed_escape <value>: escape a replacement for sed with | as delimiter.
_sed_escape() { printf '%s' "$1" | sed -e 's/[\&|]/\&/g'; }

# render_text: copy stdin to stdout, replacing the known {{TOKENS}} with the values of the
# same-named variables. Unknown tokens are left as they are.
render_text() {
  local t
  local -a sedargs=()
  for t in $TEMPLATE_TOKENS; do
    sedargs+=(-e "s|{{${t}}}|$(_sed_escape "${!t-}")|g")
  done
  sed "${sedargs[@]}"
}

# render_tree <src> <dst>: copy src into dst, rendering text files with render_text.
# Exit 5 on an unknown token (names file and token). Binary files are copied untouched.
render_tree() {
  local src=$1 dst=$2 f rel tok t known
  [[ -d "$src" ]] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    mkdir -p "$dst/$(dirname "$rel")"
    if [[ -L "$f" ]] || { [[ -s "$f" ]] && ! grep -Iq . "$f"; }; then
      cp -a "$f" "$dst/$rel"
      continue
    fi
    while IFS= read -r tok; do
      [[ -n "$tok" ]] || continue
      known=0
      for t in $TEMPLATE_TOKENS; do
        [[ "$tok" == "{{$t}}" ]] && known=1
      done
      [[ $known -eq 1 ]] || die 5 "unknown template token $tok in $f"
    done < <(grep -oE '\{\{[A-Z_]+\}\}' "$f" | sort -u || true)
    render_text <"$f" >"$dst/$rel"
    [[ -x "$f" ]] && chmod +x "$dst/$rel"
  done < <(find "$src" \( -type f -o -type l \) -print0 | sort -z)
  return 0
}
