#!/usr/bin/env bash
# Put back the Key Vault objects the Ansible track's playbooks read, after ./lab.sh resume (which
# recreates the dev vault empty) or whenever they went missing:
#   an-07  secret app-greeting (a new random value; the old one went with the old vault)
#   an-08  your Key Vault Certificates Officer role on the vault, and the certificate web-tls
# Each one only once its task was started, or once your ansible/ uses it. Idempotent: what
# exists is kept. Run it from the lab directory, next to lab.sh:
#   tracks/ansible/lib/keyvault-prereqs.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"
# shellcheck source=/dev/null
source "$root/lib/common.sh"
# shellcheck source=/dev/null
source "$root/lib/config.sh"
load_config
# shellcheck source=/dev/null
source "$root/tracks/ansible/lib/ansible.sh"
need az python3
an_kv_prereqs
echo "keyvault-prereqs: done; run ansible-playbook site.yml to deploy the values"
