#!/usr/bin/env bash
# an-08 setup (./lab.sh next), as you (az login): the platform team grants you Key Vault
# Certificates Officer on the dev vault kv-<prefix>-dev-<suffix> (az, no Terraform change) and
# creates the self-signed certificate web-tls there with a Key Vault policy (CN=acme-web.internal,
# SANs for both web VMs, 12 months, PEM). An existing certificate is never recreated. Waits for
# the new role to reach the data plane and for the certificate to be issued (up to ~10 minutes
# the first time). Idempotent.
set -euo pipefail
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"
an_kv_cert_ensure
echo "an-08: see it with: az keyvault certificate show --vault-name kv-$PREFIX-dev-$SUFFIX -n web-tls"
