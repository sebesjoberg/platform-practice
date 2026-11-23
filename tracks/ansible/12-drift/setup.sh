#!/usr/bin/env bash
# an-12 setup (./lab.sh next): the incident, made the way a teammate with sudo would: over SSH
# through the jump host (your inventory), on vm-<prefix>-web-dev-2 only:
#   - /etc/nginx/nginx.conf edited by hand: worker_connections 1
#   - nginx stopped (HAProxy then takes the server out of the pool by itself)
# The first run records the time in $LAB_HOME/snapshots/an-12.start and injects; later runs never
# inject again, so they can't undo your remediation. Prints only what the on-call person reports.
# Idempotent.
set -euo pipefail
: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${LIVE_DIR:?LIVE_DIR not set; run ./lab.sh init}"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
marker="$LAB_HOME/snapshots/an-12.start"
host="vm-$PREFIX-web-dev-2"

if [[ ! -s "$marker" ]]; then
  cd "$LIVE_DIR"
  if ! an_run ansible "$host" -b -m ansible.builtin.shell \
    -a "sed -i -E 's/worker_connections[[:space:]]+[0-9]+;/worker_connections 1;/' /etc/nginx/nginx.conf && systemctl stop nginx" >/dev/null; then
    echo "an-12: could not reach $host through your inventory (VMs running? ./lab.sh resume; cd ansible && ansible $host -m ping)" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$marker")"
  date +%s >"$marker"
fi

cat <<EOF
Message from Sam (on call):

  "HAProxy paged twice last night: $host dropped out of the pool around 02:40 and never came
   back. Traffic is all on web-dev-1 now. Someone was on that box 'tuning' things by hand during
   the night and nobody remembers what. Can you find out what differs from the repo, put it
   right, and give us a way to spot this kind of thing before the pager does?"
EOF
