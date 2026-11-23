#!/usr/bin/env bash
# tf-30 setup (./lab.sh next): save the mechanical part of the upgrade to $LAB_HOME/starter/tf-30
# (outside the repos, so catchup still finds them clean), rendered from this task's reference with
# your config so they never drift:
#   live/terraform/<stack>/versions.tf   pins ~> 5.14 and each stack's resource_providers_to_register
#   live/terraform/<stack>/.terraform.lock.hcl   locked for linux_amd64 and windows_amd64, made with
#                                        terraform providers lock (saves downloading azurerm for
#                                        both platforms in every stack, about 12 downloads)
#   modules/<module>/versions.tf         >= 5.14, < 6.0
# The lesson (the guide, the breaking changes, the release, lock files, Dependabot) stays with the
# learner. Overwrites only the starter copy. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${LAB_ROOT:-$(cd "$here/../../.." && pwd)}"
: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
# shellcheck source=/dev/null
source "$root/lib/template.sh"
ref="$here/reference"
dst="$LAB_HOME/starter/tf-30"
rm -rf "$dst"
for f in "$ref"/live/terraform/*/versions.tf "$ref"/live/terraform/*/.terraform.lock.hcl "$ref"/modules/*/versions.tf; do
  rel="${f#"$ref"/}"
  mkdir -p "$dst/$(dirname "$rel")"
  render_text <"$f" >"$dst/$rel"
done
echo "tf-30: starters saved to $dst (each stack's versions.tf and lock file, each module's versions.tf). Compare, then copy:"
echo "  diff -r $dst/live/terraform \"\$LIVE_DIR/terraform\" | grep -v '^Only in'"
echo "  for d in $dst/live/terraform/*/; do cp \"\$d\"versions.tf \"\$d\".terraform.lock.hcl \"\$LIVE_DIR/terraform/\$(basename \"\$d\")/\"; done"
echo "  for m in spoke app-env linux-vm; do cp $dst/modules/\$m/versions.tf \"\$MODULES_DIR/\$m/\"; done"
