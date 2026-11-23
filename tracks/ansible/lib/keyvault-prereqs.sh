#!/usr/bin/env bash
# Put back the Key Vault objects the Ansible track's playbooks read. ./lab.sh pause destroys the
# dev vault and ./lab.sh resume recreates it empty; resume calls this script before it re-runs
# site.yml. Run it by hand when that step failed or the objects went missing:
#   tracks/ansible/lib/keyvault-prereqs.sh
#
#   an-07  secret app-greeting (a new random value; the old one went with the old vault)
#   an-08  your Key Vault Certificates Officer role on the vault, and the certificate web-tls
# Each one only once its task was started ($LAB_HOME/progress), or once ansible/ in $LIVE_DIR
# uses it. Idempotent: what exists is kept, nothing is overwritten.
#
# Non-interactive (no prompts, stdin unused), independent of the current directory. Config: the
# environment when PREFIX, SUFFIX and LIVE_DIR are set (as when lab.sh calls it), otherwise
# $LAB_HOME/config.env (default ~/.platform-lab). Exit codes:
#   0  done (or nothing to do)
#   1  an Azure call failed (az login? vault missing?); nothing was created blindly
#   3  a tool is missing (az, python3)
set -euo pipefail
exec </dev/null

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"
# shellcheck source=/dev/null
source "$root/lib/common.sh"
if [[ -z "${PREFIX:-}" || -z "${SUFFIX:-}" || -z "${LIVE_DIR:-}" ]]; then
  # shellcheck source=/dev/null
  source "$root/lib/config.sh"
  load_config
fi
export PREFIX SUFFIX LIVE_DIR
# shellcheck source=/dev/null
source "$root/tracks/ansible/lib/ansible.sh"
need az python3
if ! an_kv_prereqs; then
  echo "keyvault-prereqs: failed; check az login (az account show) and that the dev vault exists" >&2
  exit 1
fi
echo "keyvault-prereqs: done"
