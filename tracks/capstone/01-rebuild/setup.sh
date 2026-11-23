#!/usr/bin/env bash
# cap-01 setup (./lab.sh next): the incident. A cleanup script deleted vm-<prefix>-web-dev-2,
# its OS disk and its NIC (az, as in the portal). The first run records the time and the VM's
# IDs in $LAB_HOME/snapshots/cap-01.ids (the grader wants a new VM and a pipeline run after it),
# then deletes. Later runs finish a deletion that was interrupted, and never touch a VM that was
# rebuilt since (another vmId). Prints only what the teammate would say. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
export LAB_HOME
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/web-vm.sh"

rg="$(cap01_rg)" vm="$(cap01_vm)" snap="$(cap01_snap)"
ids="$(cap01_vm_ids)" || { echo "cap-01: cannot list the VMs in $rg (az login? ./lab.sh resume?)" >&2; exit 1; }
vm_id="" disk="" nic=""
[[ -z "$ids" ]] || IFS=$'\t' read -r vm_id disk nic <<<"$ids"

if [[ -s "$snap" ]]; then
  # The incident already happened. Finish it unless the VM was rebuilt since.
  if [[ -z "$vm_id" || "$vm_id" == "$(cap01_snap_get vm_id)" ]]; then
    cap01_delete_vm "$(cap01_snap_get os_disk)" "$(cap01_snap_get nic)"
  fi
else
  [[ -n "$vm_id" ]] || {
    echo "cap-01: $vm not found in $rg: is the lab paused (./lab.sh resume)? Without the an-20 state: ./lab.sh catchup an-20" >&2
    exit 1
  }
  mkdir -p "$(dirname "$snap")"
  printf 'start=%s\nvm_id=%s\nos_disk=%s\nnic=%s\n' "$(date +%s)" "$vm_id" "$disk" "$nic" >"$snap.tmp"
  mv "$snap.tmp" "$snap"
  cap01_delete_vm "$disk" "$nic"
fi

cat <<EOF
Message from Sam (on call):

  "HAProxy on the jump host has shown $vm DOWN since last night, and the portal can't find
   the VM, its disk or its NIC any more. Nobody merged anything. We're running on one web
   server."
EOF
