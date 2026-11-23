#!/usr/bin/env bash
# tf-25 setup (./lab.sh next): save the starters to $LAB_HOME/starter/tf-25 (outside the repos,
# so catchup still finds them clean), copied from this task's reference so they never drift:
#   linux-vm/   versions, variables, outputs, tests, and a README whose generated section is
#               empty (terraform-docs fills it); the learner writes main.tf
#   live/       the two input-variable files for terraform/shared and terraform/env-dev
# and make sure the lab's SSH key pair ~/.ssh/<prefix>_lab exists. Never overwrites a key.
# Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${GH_OWNER:?GH_OWNER not set; run ./lab.sh init}"
: "${MODULES_REPO:?MODULES_REPO not set; run ./lab.sh init}"
ref="$here/reference"
dst="$LAB_HOME/starter/tf-25"
rm -rf "$dst"
mkdir -p "$dst/linux-vm/tests" "$dst/live/terraform/shared" "$dst/live/terraform/env-dev"
for rel in versions.tf variables.tf outputs.tf tests/linux-vm.tftest.hcl; do
  cp "$ref/modules/linux-vm/$rel" "$dst/linux-vm/$rel"
done
sed -e '/<!-- BEGIN_TF_DOCS -->/,/<!-- END_TF_DOCS -->/{//!d;}' \
  -e "s|{{GH_OWNER}}|$GH_OWNER|g" -e "s|{{MODULES_REPO}}|$MODULES_REPO|g" \
  "$ref/modules/linux-vm/README.md" >"$dst/linux-vm/README.md"
for s in shared env-dev; do
  cp "$ref/live/terraform/$s/variables-access.tf" "$dst/live/terraform/$s/variables-access.tf"
done
echo "tf-25: starters saved to $dst"
echo "tf-25:   cp -rn $dst/linux-vm \"\$MODULES_DIR/\""
echo "tf-25:   cp -rn $dst/live/terraform/. \"\$LIVE_DIR/terraform/\""

key="$HOME/.ssh/${PREFIX}_lab"
if [[ -f "$key" ]]; then
  echo "tf-25: kept your SSH key $key"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "${PREFIX}-lab" -f "$key"
  echo "tf-25: generated $key and $key.pub (the private key never goes into a repo)"
fi
