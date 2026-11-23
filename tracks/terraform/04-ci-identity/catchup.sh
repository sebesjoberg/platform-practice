#!/usr/bin/env bash
# tf-04 catchup (after-push, cwd = LIVE_DIR): make sure the repo uses immutable OIDC subjects
# (what the reference derives), then apply terraform/bootstrap with its remote state. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
prefix="$(gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null || true)"
if [[ "$prefix" != *@* ]]; then
  echo "tf-04: opting $repo in to immutable OIDC subject claims"
  gh api -X PUT "repos/$repo/actions/oidc/customization/sub" -F use_default=true -F use_immutable_subject=true >/dev/null
fi

cd terraform/bootstrap
for i in 1 2 3 4 5; do
  if terraform init -input=false </dev/null && terraform apply -auto-approve -input=false </dev/null; then
    exit 0
  fi
  echo "tf-04: bootstrap apply failed (attempt $i/5), retrying in 30s" >&2
  sleep 30
done
echo "tf-04: bootstrap apply failed" >&2
exit 1
