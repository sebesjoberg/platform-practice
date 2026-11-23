#!/usr/bin/env bash
# Probe (an-08), runs as root on a web VM: nginx listens on 443, and every private key its
# configuration names (ssl_certificate_key) is a root-owned file with no group/other permissions
# (0600, 0400, ...).
set -euo pipefail
conf="$(nginx -T 2>/dev/null)"
grep -qE '^[[:space:]]*listen[[:space:]]+([^;]*:)?443[[:space:]]+[^;]*ssl' <<<"$conf"
keys="$(sed -nE 's/^[[:space:]]*ssl_certificate_key[[:space:]]+([^;]+);.*/\1/p' <<<"$conf" | sort -u)"
[[ -n "$keys" ]]
while IFS= read -r k; do
  [[ "$(stat -c '%U' "$k")" == root && "$(stat -c '%a' "$k")" =~ ^[0-7]?[0-7]00$ ]]
done <<<"$keys"
