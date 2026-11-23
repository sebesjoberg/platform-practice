#!/usr/bin/env bash
# an-09 setup (./lab.sh next): save the app's three releases to $LAB_HOME/starter/an-09/releases
# (outside the repos, so catchup still finds them clean), copied from this task's reference so
# they never drift:
#   1.0.0/acme_hello.py   the first release
#   1.1.0/acme_hello.py   the next one (an-11 rolls it out)
#   broken/acme_hello.py  starts, but every request answers 500 (an-18)
# Overwrites only the starter copy. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
src="$here/reference/live/ansible/roles/acme_hello/files/releases"
dst="$LAB_HOME/starter/an-09/releases"
rm -rf "$dst"
mkdir -p "$dst"
cp -R "$src/." "$dst/"
echo "an-09: the app's releases are in $dst. Copy them into your role:"
echo "  mkdir -p \"\$LIVE_DIR/ansible/roles/acme_hello/files\" && cp -R $dst \"\$LIVE_DIR/ansible/roles/acme_hello/files/\""
