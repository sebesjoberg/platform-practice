#!/usr/bin/env bash
# tf-26 setup (./lab.sh next): the incident. A teammate's portal-made resources, created with az:
#   rg-<prefix>-legacy           tags owner/env/managed_by=clickops (the owner-tag policy of tf-11
#                                denies an rg-* group without an owner tag)
#   st<prefix>legacy<suffix>     Standard_LRS StorageV2, TLS 1.2, HTTPS only, no public blob access
# and the account's ID and creation time in $LAB_HOME/snapshots/tf-26.ids (the grader proves the
# import didn't recreate it). Creates only what is missing and keeps the first snapshot, so it
# never undoes the learner's work. Prints only what the teammate would say. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
: "${SUFFIX:?SUFFIX not set; run ./lab.sh init}"
: "${OWNER_TAG:?OWNER_TAG not set; run ./lab.sh init}"
location="${LOCATION:-swedencentral}"
rg="rg-$PREFIX-legacy"
sa="st${PREFIX}legacy$SUFFIX"
snap="$LAB_HOME/snapshots/tf-26.ids"
tags=(owner="$OWNER_TAG" env=prod managed_by=clickops)

if [[ "$(az group exists -n "$rg" -o tsv | tr -d '\r')" != true ]]; then
  az group create -n "$rg" -l "$location" --tags "${tags[@]}" -o none
fi
if ! az storage account show -g "$rg" -n "$sa" -o none 2>/dev/null; then
  az storage account create -g "$rg" -n "$sa" -l "$location" --sku Standard_LRS --kind StorageV2 \
    --access-tier Hot --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false \
    --allow-cross-tenant-replication false --tags "${tags[@]}" -o none
fi
if [[ ! -s "$snap" ]]; then
  mkdir -p "$(dirname "$snap")"
  az storage account show -g "$rg" -n "$sa" --query "[id, creationTime]" -o tsv | tr -d '\r' >"$snap.tmp"
  mv "$snap.tmp" "$snap"
fi

cat <<EOF
Message from Sam (operations):

  "Hi! Before we had the platform I set up a storage account for finance in the portal:
   $sa in $rg. They upload their invoice exports to it every week. The auditors
   flagged it today: everything we run has to be in Terraform and go through review. Can you
   take it over? Please don't recreate it, the files have to stay."
EOF
