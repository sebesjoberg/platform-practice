#!/usr/bin/env bash
# tf-28 catchup (cwd = LIVE_DIR): release the incident's stale lock on env-dev.tfstate, as
# terraform force-unlock does: remove the terraformlockid metadata entry, then release the lease.
# Only the lock setup.sh created ($LAB_HOME/snapshots/tf-28.lock holds its ID): a lock with any
# other ID belongs to a real run and is left alone. tf-05's catchup calls this before it
# dispatches the pipeline (a stale lock would fail the env-dev apply); without the snapshot, or
# once released, it does nothing. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
snap="$LAB_HOME/snapshots/tf-28.lock"
[[ -s "$snap" ]] || exit 0
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
blobargs=(--auth-mode login --account-name "st${PREFIX}tfstate$SUFFIX" --container-name tfstate --name env-dev.tfstate)
id="$(head -n1 "$snap")"

[[ "$(az storage blob show "${blobargs[@]}" --query properties.lease.state -o tsv | tr -d '\r')" == leased ]] || {
  echo "tf-28: env-dev.tfstate is not locked"
  exit 0
}
held="$(az storage blob metadata show "${blobargs[@]}" -o json | jq -r '.terraformlockid // empty' | base64 -d 2>/dev/null | jq -r '.ID // empty' || true)"
if [[ "$held" != "$id" ]]; then
  echo "tf-28: env-dev.tfstate is locked by ${held:-an unknown holder}, not by the incident; leaving it alone" >&2
  exit 0
fi
az storage blob metadata update "${blobargs[@]}" --lease-id "$id" -o none
az storage blob lease release --auth-mode login --account-name "st${PREFIX}tfstate$SUFFIX" \
  --container-name tfstate --blob-name env-dev.tfstate --lease-id "$id" -o none
echo "tf-28: released the stale lock $id on env-dev.tfstate"
