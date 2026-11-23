#!/usr/bin/env bash
# tf-03 catchup (after-push, cwd = LIVE_DIR): move bootstrap's local state into the azurerm
# backend and delete the stale local files. Retries while a fresh blob data role propagates.
# Idempotent: once the backend is initialised, init changes nothing.
set -euo pipefail

cd terraform/bootstrap
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if terraform init -input=false -migrate-state -force-copy </dev/null; then
    ok=1
    break
  fi
  echo "tf-03: backend init failed (attempt $i/10; a new role assignment can take minutes), retrying in 30s" >&2
  sleep 30
done
[[ $ok -eq 1 ]] || { echo "tf-03: could not initialise the azurerm backend" >&2; exit 1; }

# Only remove the local copies once the remote state really holds the resources.
if terraform state pull </dev/null | jq -e '(.resources // []) | length > 0' >/dev/null; then
  rm -f terraform.tfstate terraform.tfstate.backup
else
  echo "tf-03: remote state is empty; keeping local state files" >&2
  exit 1
fi
