#!/usr/bin/env bash
# tf-04 catchup (after-push, cwd = LIVE_DIR): make sure the repo uses immutable OIDC subjects
# (what the reference derives), then apply terraform/bootstrap with its remote state. Idempotent.
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"
# Opt in only when GitHub positively reports a legacy (name-based) prefix. A failed GET or an
# absent field changes nothing: the reference builds the immutable prefix from the repo API.
if prefix="$(gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty' 2>/dev/null)" &&
  [[ -n "$prefix" && "$prefix" != *@* ]]; then
  echo "tf-04: opting $repo in to immutable OIDC subject claims (was $prefix)"
  gh api -X PUT "repos/$repo/actions/oidc/customization/sub" -F use_default=true -F use_immutable_subject=true >/dev/null ||
    echo "tf-04: could not opt in; continuing with the API-built prefix" >&2
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
