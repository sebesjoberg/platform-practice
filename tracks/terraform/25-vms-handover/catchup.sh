#!/usr/bin/env bash
# tf-25 catchup (after-push, cwd = LIVE_DIR): the SSH key pair and the two repo variables the
# pipeline needs. The private key is ~/.ssh/<prefix>_lab, outside every repo; it is generated
# here only if missing and never leaves this machine. tf-05's hook runs this script before it
# dispatches the workflow whenever the workflow references these variables. It also tags v2.2.0
# (normally already done by tf-05's hook). Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
key="$HOME/.ssh/${PREFIX}_lab"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ ! -f "$key" ]]; then
  ssh-keygen -q -t ed25519 -N "" -C "${PREFIX}-lab" -f "$key"
  echo "tf-25: generated the SSH key pair $key (private key stays here, never commit it)"
elif [[ ! -f "$key.pub" ]]; then
  ssh-keygen -y -f "$key" >"$key.pub"
fi
gh variable set SSH_PUBLIC_KEY -R "$repo" --body "$(cat "$key.pub")"
[[ -n "${LEARNER_IP:-}" ]] || { echo "tf-25: LEARNER_IP is not set; run ./lab.sh init --refresh-ip" >&2; exit 1; }
gh variable set LEARNER_IP -R "$repo" --body "$LEARNER_IP"
echo "tf-25: repo variables SSH_PUBLIC_KEY ($key.pub) and LEARNER_IP ($LEARNER_IP) are set"

if [[ "${CATCHUP_PHASE:-}" == after-push && -d "${MODULES_DIR:-}/.git" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/modules-tag.sh"
  modules_tag v2.2.0
fi
