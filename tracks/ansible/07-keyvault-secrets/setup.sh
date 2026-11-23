#!/usr/bin/env bash
# an-07 setup (./lab.sh next): the app team stores the secret app-greeting in the dev vault
# kv-<prefix>-dev-<suffix>, with a random value, as you (az login; tf-21 made you Key Vault
# Secrets Officer on the subscription). An existing value is never overwritten. The value is
# recorded in $LAB_HOME/snapshots/an-07.value (mode 0600) for the grader. Idempotent.
set -euo pipefail
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_kv_secret_ensure
echo "an-07: your playbook reads it at run time; the value never goes into a file in the repo"
