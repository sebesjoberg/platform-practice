#!/usr/bin/env bash
# tf-21 setup (./lab.sh next): save the starters to $LAB_HOME/starter/tf-21, copied from this
# task's reference so they never drift, outside the repos so catchup still finds them clean
# (same as tf-19):
#   modules/app-env/                 versions, variables, outputs, tests (main.tf is the lesson)
#   modules/.trivyignore.yaml        the accepted AZU-0013 finding, with its reason
#   modules/.github/workflows/ci.yml tf-19's CI plus trivy --ignorefile .trivyignore.yaml
#   live/terraform/bootstrap/platform-owner.tf   your Key Vault Secrets Officer role
# Overwrites only the starter copy. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
ref="$here/reference"
dst="$LAB_HOME/starter/tf-21"
rm -rf "$dst"
for rel in modules/app-env/versions.tf modules/app-env/variables.tf modules/app-env/outputs.tf \
  modules/app-env/tests/app-env.tftest.hcl modules/.trivyignore.yaml modules/.github/workflows/ci.yml \
  live/terraform/bootstrap/platform-owner.tf; do
  mkdir -p "$(dirname "$dst/$rel")"
  cp "$ref/$rel" "$dst/$rel"
done
echo "tf-21: starters saved to $dst. Copy them:"
echo "  cp -rn $dst/modules/app-env \"\$MODULES_DIR/\""
echo "  cp $dst/modules/.trivyignore.yaml \"\$MODULES_DIR/\""
echo "  cp $dst/modules/.github/workflows/ci.yml \"\$MODULES_DIR/.github/workflows/ci.yml\""
echo "  cp -n $dst/live/terraform/bootstrap/platform-owner.tf \"\$LIVE_DIR/terraform/bootstrap/\""
