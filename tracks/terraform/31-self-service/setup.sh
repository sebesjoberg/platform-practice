#!/usr/bin/env bash
# tf-31 setup (./lab.sh next): save the starters to $LAB_HOME/starter/tf-31 (outside the repos, so
# catchup still finds them clean), rendered from this task's reference with your config so they
# never drift:
#   team-env/        versions, variables, outputs, tests, and a README whose generated section is
#                    empty (terraform-docs fills it); the learner writes main.tf
#   live/terraform/  teams/payments/versions.tf and variables.tf (the learner writes the module
#                    call) and bootstrap/team-onboarding.tf (CI may assign Contributor to managed
#                    identities)
# Overwrites only the starter copy. Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${LAB_ROOT:-$(cd "$here/../../.." && pwd)}"
: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
# shellcheck source=/dev/null
source "$root/lib/template.sh"
ref="$here/reference"
dst="$LAB_HOME/starter/tf-31"
rm -rf "$dst"
mkdir -p "$dst/team-env/tests" "$dst/live/terraform/teams/payments" "$dst/live/terraform/bootstrap"
for rel in versions.tf variables.tf outputs.tf tests/team-env.tftest.hcl; do
  render_text <"$ref/modules/team-env/$rel" >"$dst/team-env/$rel"
done
sed -e '/<!-- BEGIN_TF_DOCS -->/,/<!-- END_TF_DOCS -->/{//!d;}' "$ref/modules/team-env/README.md" |
  render_text >"$dst/team-env/README.md"
for rel in teams/payments/versions.tf teams/payments/variables.tf bootstrap/team-onboarding.tf; do
  render_text <"$ref/live/terraform/$rel" >"$dst/live/terraform/$rel"
done
echo "tf-31: starters saved to $dst"
echo "tf-31:   cp -rn $dst/team-env \"\$MODULES_DIR/\""
echo "tf-31:   cp -rn $dst/live/terraform/. \"\$LIVE_DIR/terraform/\""
