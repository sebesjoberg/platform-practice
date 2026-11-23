#!/usr/bin/env bash
# Probe (an-09), runs as root on a web VM: acme-hello.service is active, not as root, rated below
# 5.0 by systemd-analyze security, and /health answers "ok $1" on 127.0.0.1:8080 and through
# nginx on port 80.
set -euo pipefail
version=$1
unit=acme-hello.service
systemctl is-active -q "$unit"
user="$(systemctl show -p User --value "$unit")"
dyn="$(systemctl show -p DynamicUser --value "$unit")"
[[ "$dyn" == yes || (-n "$user" && "$user" != root && "$user" != 0) ]]
systemd-analyze security --threshold=49 "$unit" >/dev/null 2>&1
[[ "$(curl -fsS --max-time 5 http://127.0.0.1:8080/health)" == "ok $version" ]]
[[ "$(curl -fsS --max-time 5 http://127.0.0.1/health)" == "ok $version" ]]
