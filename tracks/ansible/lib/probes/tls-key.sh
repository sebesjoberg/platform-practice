#!/usr/bin/env bash
# Probe (an-08), runs as root on a web VM: nginx listens on 443, and every private key its
# configuration names (ssl_certificate_key) is a root-owned file with mode 0600.
set -euo pipefail
conf="$(nginx -T 2>/dev/null)"
grep -qE '^[[:space:]]*listen[[:space:]]+([^;]*:)?443[[:space:]]+[^;]*ssl' <<<"$conf"
keys="$(sed -nE 's/^[[:space:]]*ssl_certificate_key[[:space:]]+([^;]+);.*/\1/p' <<<"$conf" | sort -u)"
[[ -n "$keys" ]]
while IFS= read -r k; do
  [[ "$(stat -c '%a %U' "$k")" == "600 root" ]]
done <<<"$keys"
