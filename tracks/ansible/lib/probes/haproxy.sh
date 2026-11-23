#!/usr/bin/env bash
# Probe (an-10), runs as root on the jump host: HAProxy's configuration is valid, has a backend
# web and the admin socket at /run/haproxy/admin.sock (mode 660, group haproxy, level admin), and
# 10 requests to
# port 80 reach every web server named in the arguments.
set -euo pipefail
cfg=/etc/haproxy/haproxy.cfg
systemctl is-active -q haproxy
haproxy -c -q -f "$cfg"
grep -qE '^[[:space:]]*backend[[:space:]]+web([[:space:]]|$)' "$cfg"
grep -qE '^[[:space:]]*stats[[:space:]]+socket[[:space:]]+/run/haproxy/admin\.sock[[:space:]].*level[[:space:]]+admin' "$cfg"
[[ "$(stat -c '%a %G' /run/haproxy/admin.sock)" == "660 haproxy" ]]
out=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  out+="$(curl -fsS --max-time 5 http://127.0.0.1/)"$'\n'
done
for h in "$@"; do
  grep -qF -- "$h" <<<"$out" || {
    echo "10 requests to port 80 never reached $h"
    exit 1
  }
done
