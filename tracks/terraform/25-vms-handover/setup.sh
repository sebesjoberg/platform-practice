#!/usr/bin/env bash
# tf-25 setup (./lab.sh next): save the linux-vm module starter (versions, variables, outputs,
# tests; the learner writes main.tf) to $LAB_HOME/starter/tf-25/linux-vm, copied from this task's
# reference so they never drift and kept outside the repos (catchup needs them clean), and make
# sure the lab's SSH key pair ~/.ssh/<prefix>_lab exists. Never overwrites a key. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
src="$here/reference/modules/linux-vm"
dst="$LAB_HOME/starter/tf-25/linux-vm"
rm -rf "$dst"
mkdir -p "$dst/tests"
for rel in versions.tf variables.tf outputs.tf tests/linux-vm.tftest.hcl; do
  cp "$src/$rel" "$dst/$rel"
done
echo "tf-25: linux-vm starter saved to $dst"
echo "tf-25: copy it into the modules repo without overwriting: cp -rn $dst \"\$MODULES_DIR/\""

key="$HOME/.ssh/${PREFIX}_lab"
if [[ -f "$key" ]]; then
  echo "tf-25: kept your SSH key $key"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "${PREFIX}-lab" -f "$key"
  echo "tf-25: generated $key and $key.pub (the private key never goes into a repo)"
fi
