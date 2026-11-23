#!/usr/bin/env bash
# Probe (an-06), runs as root on a web VM: nginx is active, its configuration is valid, and the
# page on port 80 names this host and the environment given as $1.
set -euo pipefail
env_name=$1
systemctl is-active -q nginx
nginx -t -q 2>/dev/null
page="$(curl -fsS --max-time 5 http://127.0.0.1/)"
grep -qF "$(hostname)" <<<"$page"
grep -qw -- "$env_name" <<<"$page"
