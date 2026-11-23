# shellcheck shell=bash
# Helpers for cap-01, sourced by its setup.sh, catchup.sh and checks.sh (config exported: PREFIX,
# GH_OWNER, LIVE_REPO, LAB_HOME). The VM the incident takes away is vm-<prefix>-web-dev-2.
#
# Snapshot ($LAB_HOME/snapshots/cap-01.ids), written once by setup.sh before it deletes anything:
#   start=<epoch seconds>     when the incident began
#   vm_id=<vmId>              Azure's unique ID of the deleted VM (a rebuilt VM gets a new one)
#   os_disk=<resource ID>     its OS disk (auto-named, so never reused by a rebuild)
#   nic=<resource ID>         its NIC (named after the VM: a rebuild reuses the ID)

cap01_rg() { printf 'rg-%s-dev\n' "${PREFIX:?}"; }
cap01_vm() { printf 'vm-%s-web-dev-2\n' "${PREFIX:?}"; }
cap01_snap() { printf '%s/snapshots/cap-01.ids\n' "${LAB_HOME:?}"; }

# cap01_snap_get <key>: a value from the snapshot; empty when there is none.
cap01_snap_get() {
  local f
  f="$(cap01_snap)"
  [[ -f "$f" ]] || return 0
  sed -n "s/^$1=//p" "$f" | head -n1
}

# cap01_vm_ids: "<vmId><TAB><OS disk ID><TAB><NIC ID>" of the VM, or nothing when it doesn't
# exist. Fails (status 1) only when az fails, e.g. the resource group is missing.
cap01_vm_ids() {
  az vm list -g "$(cap01_rg)" \
    --query "[?name=='$(cap01_vm)'].[vmId, storageProfile.osDisk.managedDisk.id, networkProfile.networkInterfaces[0].id]" -o tsv
}

# cap01_delete_vm <OS disk ID> <NIC ID>: delete the VM (if it exists), then its OS disk and NIC,
# as a cleanup script in the portal would. The NIC only while no VM uses it: a rebuilt VM reuses
# its name and ID. Idempotent.
cap01_delete_vm() {
  local disk=$1 nic=$2 used
  if [[ -n "$(cap01_vm_ids)" ]]; then
    az vm delete -g "$(cap01_rg)" -n "$(cap01_vm)" --yes -o none
  fi
  if [[ -n "$disk" ]] && az disk show --ids "$disk" --query id -o tsv >/dev/null 2>&1; then
    az disk delete --ids "$disk" --yes -o none
  fi
  if [[ -n "$nic" ]] && used="$(az network nic show --ids "$nic" --query "virtualMachine.id" -o tsv 2>/dev/null)"; then
    [[ -n "$used" ]] || az network nic delete --ids "$nic" -o none
  fi
}

# cap01_vm_keys: the public keys Azure authorized for the VM's admin user, one per line.
cap01_vm_keys() {
  az vm show -g "$(cap01_rg)" -n "$(cap01_vm)" --query "osProfile.linuxConfiguration.ssh.publicKeys[].keyData" -o tsv
}

# cap01_key_body <key line>: "<type> <base64>" without the comment, for comparing keys.
cap01_key_body() {
  awk '{ print $1, $2 }' <<<"$1"
}

# cap01_vm_has_key <key line>: the VM authorizes that key for its admin user.
cap01_vm_has_key() {
  local want k
  want="$(cap01_key_body "$1")"
  while IFS= read -r k; do
    [[ -n "$k" && "$(cap01_key_body "$k")" == "$want" ]] && return 0
  done < <(cap01_vm_keys 2>/dev/null)
  return 1
}

# cap01_runner_pubkey: the public half of gh-runner's SSH key on the jump host (an-15), read
# through your inventory (cwd = LIVE_DIR; needs tracks/ansible/lib/ansible.sh). The private half
# never leaves the jump host.
cap01_runner_pubkey() {
  an_run ansible role_jump -b -m ansible.builtin.command -a "cat /home/gh-runner/.ssh/id_ed25519.pub" 2>/dev/null |
    grep -m1 -E '^(ssh-ed25519|ssh-rsa) '
}

# cap01_repo_var <name>: the value of a repo variable of the live repo; empty when it's unset.
cap01_repo_var() {
  gh api "repos/${GH_OWNER:?}/${LIVE_REPO:?}/actions/variables/$1" --jq .value 2>/dev/null || true
}
