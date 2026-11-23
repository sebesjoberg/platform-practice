#!/usr/bin/env bash
# tf-19 setup (./lab.sh next): put the modules repo's CI workflow where the learner can copy it
# from. The repo doesn't exist yet (creating it is the task), so the starter goes to
# $LAB_HOME/starter/tf-19/ci.yml. Overwrites only that file. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_HOME:=$HOME/.platform-lab}"
dst="$LAB_HOME/starter/tf-19/ci.yml"
mkdir -p "$(dirname "$dst")"
cp "$here/starter/ci.yml" "$dst"
echo "tf-19: CI workflow for the modules repo saved to $dst (copy it to .github/workflows/ci.yml there)"
