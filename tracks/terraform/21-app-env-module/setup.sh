#!/usr/bin/env bash
# tf-21 setup (./lab.sh next): save the app-env module starter (versions, variables, outputs and
# the tests, which describe what main.tf must build) to $LAB_HOME/starter/tf-21/app-env, for the
# learner to copy into the modules repo. Copied from this task's reference, so starter and
# reference never drift. Outside the repos, so catchup still finds them clean (same as tf-19).
# Overwrites only the starter copy. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
src="$here/reference/modules/app-env"
dst="$LAB_HOME/starter/tf-21/app-env"
rm -rf "$dst"
mkdir -p "$dst/tests"
for rel in versions.tf variables.tf outputs.tf tests/app-env.tftest.hcl; do
  cp "$src/$rel" "$dst/$rel"
done
echo "tf-21: app-env starter saved to $dst"
echo "tf-21: copy it into the modules repo without overwriting: cp -rn $dst \"\$MODULES_DIR/\""
