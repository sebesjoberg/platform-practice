#!/usr/bin/env bash
# cap-01 catchup (after-push, cwd = LIVE_DIR), as you (gh, az, your inventory). The reference
# tree is pushed and the earlier hooks have run (the pipeline applied it, the runner is
# registered). The non-file steps of the capstone:
#   1. the repo variable RUNNER_SSH_PUBLIC_KEY = gh-runner's public key, read on the jump host
#   2. vm-<prefix>-web-dev-2 must authorize that key for azureuser. A VM built before the
#      variable held it can't (linux-vm v3.2.0 never changes the keys of a running VM), so it is
#      deleted the way setup.sh's incident deletes it, and the pipeline below rebuilds it
#   3. a terraform.yml run on main (stacks env-dev), then the ansible.yml run it triggers
#      (workflow_run), which must configure the rebuilt VM with no help: both waited for
# Idempotent: a VM with the key is left alone; the two runs change nothing on a converged fleet.
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$here/../lib/web-vm.sh"
# shellcheck source=/dev/null
source "$here/../../ansible/lib/ansible.sh"
# shellcheck source=/dev/null
source "$here/../../ansible/lib/ci.sh"
repo="${GH_OWNER:?}/${LIVE_REPO:?}"

key="$(cap01_runner_pubkey)" || {
  echo "cap-01: could not read /home/gh-runner/.ssh/id_ed25519.pub on vm-$PREFIX-jump (an-15's runner.yml?)" >&2
  exit 1
}
if [[ "$(cap01_key_body "$(cap01_repo_var RUNNER_SSH_PUBLIC_KEY)")" != "$(cap01_key_body "$key")" ]]; then
  gh variable set RUNNER_SSH_PUBLIC_KEY -R "$repo" --body "$key"
  echo "cap-01: repo variable RUNNER_SSH_PUBLIC_KEY = gh-runner's public key on vm-$PREFIX-jump"
fi

ids="$(cap01_vm_ids)"
if [[ -n "$ids" ]] && ! cap01_vm_has_key "$key"; then
  IFS=$'\t' read -r _ disk nic <<<"$ids"
  echo "cap-01: $(cap01_vm) predates the runner's key; deleting it so the pipeline rebuilds it with the key"
  cap01_delete_vm "$disk" "$nic"
fi

ci_dispatch_wait "$repo" env-dev cap-01
# The ansible.yml run starts when the terraform.yml run completes, a few seconds before
# ci_dispatch_wait (polling) sees it: look back a minute.
since="$(date -u -d "@$(($(date +%s) - 60))" +%Y-%m-%dT%H:%M:%SZ)"
id=""
for _ in $(seq 1 60); do
  id="$(gh api "repos/$repo/actions/workflows/ansible.yml/runs?created=%3E%3D$since&per_page=20" \
    --jq '[.workflow_runs[] | select(.event == "workflow_run" or .event == "repository_dispatch")][0].id // empty')"
  [[ -n "$id" ]] && break
  sleep "${CI_POLL_SECONDS:-10}"
done
[[ -n "$id" ]] || {
  echo "cap-01: the terraform.yml run did not trigger ansible.yml (workflow_run on main?)" >&2
  exit 1
}
echo "cap-01: waiting for ansible.yml run $id (triggered by the terraform run)"
ci_wait_run "$repo" "$id" || {
  echo "cap-01: ansible.yml run $id failed; see gh run view $id -R $repo --log-failed" >&2
  exit 1
}
an_wf_run_jobs "$repo" "$id" | jq -se 'any(.[]; .name == "apply" and .conclusion == "success")' >/dev/null || {
  echo "cap-01: ansible.yml run $id did not run its apply job" >&2
  exit 1
}
echo "cap-01: run $id configured the fleet; vm-$PREFIX-web-dev-2 is back in the HAProxy pool"
