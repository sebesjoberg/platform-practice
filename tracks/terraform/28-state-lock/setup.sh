#!/usr/bin/env bash
# tf-28 setup (./lab.sh next): the incident. A stale Terraform lock on env-dev.tfstate, exactly as
# the azurerm backend leaves one behind when a run dies between lock and unlock:
#   - an infinite blob lease whose lease ID is the lock ID (a UUID);
#   - the blob metadata entry terraformlockid = base64 of the lock info JSON
#     {"ID","Operation","Info","Who","Version","Created","Path"} (Terraform's statemgr.LockInfo;
#     see internal/backend/remote-state/azure/client.go), so terraform plan reports a real lock.
# Writes the lock ID and the time to $LAB_HOME/snapshots/tf-28.lock (catchup releases only this
# lock; the grader wants a green run after it). The first run injects; later runs never lock
# again. Refuses while a real run holds the lock. Prints only what the teammate would say.
# Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
sa="st${PREFIX}tfstate$SUFFIX"
blob=env-dev.tfstate
snap="$LAB_HOME/snapshots/tf-28.lock"
blobargs=(--auth-mode login --account-name "$sa" --container-name tfstate)

if [[ ! -s "$snap" ]]; then
  state="$(az storage blob show "${blobargs[@]}" --name "$blob" --query properties.lease.state -o tsv | tr -d '\r')"
  if [[ "$state" == leased ]]; then
    echo "tf-28: $blob is locked right now, probably by a running pipeline. Wait for it to finish, then run ./lab.sh next again." >&2
    exit 1
  fi
  id="$(cat /proc/sys/kernel/random/uuid)"
  created="$(date -u -d '-7 hours' +%Y-%m-%dT%H:%M:%S.%NZ)"
  info="$(jq -cn --arg id "$id" --arg created "$created" '{ID: $id, Operation: "OperationTypeApply", Info: "",
    Who: "sam@build-agent-07", Version: "1.17.2", Created: $created, Path: "tfstate/env-dev.tfstate"}')"
  az storage blob lease acquire "${blobargs[@]}" --blob-name "$blob" --lease-duration -1 --proposed-lease-id "$id" -o none
  az storage blob metadata update "${blobargs[@]}" --name "$blob" --lease-id "$id" \
    --metadata "terraformlockid=$(printf '%s' "$info" | base64 -w0)" -o none
  mkdir -p "$(dirname "$snap")"
  printf '%s\n%s\n' "$id" "$(date +%s)" >"$snap"
fi

cat <<'EOF'
Message from Sam (operations):

  "Hey, env-dev is stuck. Last night's apply on our old build agent died halfway (the VM got
   recycled), and since then every run fails with 'Error acquiring the state lock', yours in
   the pipeline too. Nobody is running anything right now, I checked. Can you sort it out?"
EOF
