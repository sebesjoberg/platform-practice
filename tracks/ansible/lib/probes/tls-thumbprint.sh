#!/usr/bin/env bash
# Probe (an-08), runs on the jump host: the certificate served on <ip>:443 (SNI acme-web.internal)
# has the SHA-1 thumbprint $1 (Key Vault's x509ThumbprintHex), for every <ip> after it.
set -euo pipefail
want="$(tr 'a-f' 'A-F' <<<"$1")"
shift
[[ $# -ge 1 ]]
for ip in "$@"; do
  fp="$(timeout 10 openssl s_client -connect "$ip:443" -servername acme-web.internal </dev/null 2>/dev/null |
    openssl x509 -noout -fingerprint -sha1)"
  fp="${fp#*=}"
  fp="${fp//:/}"
  [[ "$(tr 'a-f' 'A-F' <<<"$fp")" == "$want" ]] || {
    echo "$ip serves $fp, Key Vault has $want"
    exit 1
  }
done
