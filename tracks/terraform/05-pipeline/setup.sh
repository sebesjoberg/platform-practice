#!/usr/bin/env bash
# tf-05 setup (./lab.sh next): drop the starter workflow and the stack discovery script into the
# live repo. Never overwrites an existing file. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LIVE_DIR:?LIVE_DIR not set; run ./lab.sh init}"
[[ -d "$LIVE_DIR/.git" ]] || { echo "tf-05: $LIVE_DIR is not a git clone (do tf-01 first)" >&2; exit 1; }

for rel in .github/workflows/terraform.yml .github/scripts/stacks.sh; do
  dst="$LIVE_DIR/$rel"
  if [[ -e "$dst" ]]; then
    echo "tf-05: kept your existing $rel"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$here/starter/$rel" "$dst"
  if [[ "$rel" == *.sh ]]; then chmod +x "$dst"; fi
  if [[ "$rel" == *.yml ]]; then
    echo "tf-05: created $rel (starter; fill in the TODO(tf-05) parts)"
  else
    echo "tf-05: created $rel (stack discovery, ready to use)"
  fi
done
