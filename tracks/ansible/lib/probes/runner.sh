#!/usr/bin/env bash
# Probe (an-15), runs as root on the jump host: a GitHub Actions runner service is active and
# runs as gh-runner (not root); gh-runner's private key is its own (mode 600); and with that key
# gh-runner logs in as ops on every web VM private IP given as arguments (role base authorized
# the public half). Read-only.
set -euo pipefail
user=gh-runner
key="/home/$user/.ssh/id_ed25519"
unit="$(systemctl list-units --type=service --state=active --plain --no-legend 'actions.runner.*' | awk 'NR == 1 { print $1 }')"
[[ -n "$unit" ]] || {
  echo "no active actions.runner.* service"
  exit 1
}
[[ "$(systemctl show -p User --value "$unit")" == "$user" ]] || {
  echo "$unit does not run as $user"
  exit 1
}
[[ "$(stat -c '%U %a' "$key")" == "$user 600" ]] || {
  echo "$key is not $user's with mode 600"
  exit 1
}
[[ $# -ge 1 ]]
for ip in "$@"; do
  sudo -u "$user" ssh -i "$key" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "ops@$ip" true || {
    echo "$user cannot log in as ops on $ip with its key"
    exit 1
  }
done
