#!/usr/bin/env bash
# Probe (an-07), runs as root on a web VM: /etc/acme/app.env is root:acme 0640 and its
# APP_GREETING value has the SHA-256 given as $1. The grader passes a hash, never the value.
set -euo pipefail
want=$1
f=/etc/acme/app.env
[[ "$(stat -c '%a %U %G' "$f")" == "640 root acme" ]]
v="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?APP_GREETING=//p' "$f" | head -n1)"
v="${v%\"}"
v="${v#\"}"
v="${v%\'}"
v="${v#\'}"
[[ "$(printf '%s' "$v" | sha256sum | cut -d' ' -f1)" == "$want" ]]
