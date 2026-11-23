#!/usr/bin/env bash
# Bring the self-hosted runner back after ./lab.sh pause / resume (from an-15 on). Resume rebuilds
# the jump host empty: the old runner shows offline in GitHub, and the Ansible pipeline (an-16)
# has nothing to run on. This script, run as you from your machine:
#   0. cancels the ansible.yml runs waiting for a runner: they would start the moment step 1
#      registers it, before step 4 has created ops and authorized the new runner's key on the new
#      VMs, and fail (or collide with step 4). The ones the Terraform pipeline triggered
#      (workflow_run, repository_dispatch; cap-01) are remembered in $LAB_HOME/runner-register.held
#   1. registers the new jump host with a fresh registration token (runner.yml; the token goes
#      through a 0600 file that is removed afterwards, --replace takes over the old name)
#   2. from cap-01 (a workflow uses the repo variable RUNNER_SSH_PUBLIC_KEY): sets it to the new
#      runner's public key, so the next VM Terraform builds authorizes it for azureuser
#   3. puts back the Key Vault objects the playbooks read (keyvault-prereqs.sh's step)
#   4. runs site.yml, which authorizes the runner's new SSH key on every VM
#   5. re-runs the remembered triggered runs (a re-run keeps its event), which now log in as ops;
#      ./lab.sh resume dispatches a fresh run for everything else (from an-16)
# Then new ansible.yml runs work again. If a step fails, the next run of this script re-runs the
# runs remembered so far.
#   tracks/ansible/lib/runner-register.sh
#
# Non-interactive, independent of the current directory. Config from the environment when
# PREFIX, SUFFIX, GH_OWNER, LIVE_REPO and LIVE_DIR are set, otherwise $LAB_HOME/config.env.
# Exit codes: 0 done (or nothing to do: no runner.yml yet), 1 a step failed, 3 a tool is missing.
set -euo pipefail
exec </dev/null

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"
# shellcheck source=/dev/null
source "$root/lib/common.sh"
if [[ -z "${PREFIX:-}" || -z "${SUFFIX:-}" || -z "${GH_OWNER:-}" || -z "${LIVE_REPO:-}" || -z "${LIVE_DIR:-}" ]]; then
  # shellcheck source=/dev/null
  source "$root/lib/config.sh"
  load_config
fi
export PREFIX SUFFIX GH_OWNER LIVE_REPO LIVE_DIR
# shellcheck source=/dev/null
source "$root/tracks/ansible/lib/ansible.sh"
need gh az python3

cd "$LIVE_DIR"
if [[ ! -f ansible/runner.yml ]]; then
  echo "runner-register: no ansible/runner.yml in $LIVE_DIR (an-15 not done yet); nothing to do"
  exit 0
fi

repo="$GH_OWNER/$LIVE_REPO"
held="$LAB_HOME/runner-register.held"
if [[ -f .github/workflows/ansible.yml ]]; then
  pending="$(gh run list -R "$repo" --workflow ansible.yml --limit 50 --json databaseId,status,event \
    --jq '.[] | select(.status != "completed") | "\(.databaseId) \(.event)"')" || {
    echo "runner-register: could not list the ansible.yml runs (gh auth status?)" >&2
    exit 1
  }
  while read -r id ev; do
    [[ -n "$id" ]] || continue
    if gh run cancel "$id" -R "$repo" >/dev/null; then
      echo "runner-register: cancelled ansible.yml run $id ($ev) until the fleet is ready for the new runner"
      case "$ev" in
        workflow_run | repository_dispatch)
          mkdir -p "$LAB_HOME"
          echo "$id" >>"$held"
          ;;
      esac
    else
      echo "runner-register: warning: could not cancel ansible.yml run $id ($ev); it may fail once the runner is back" >&2
    fi
  done <<<"$pending"
fi

tok="$(mktemp)"
trap 'rm -f "$tok"' EXIT
chmod 600 "$tok"
gh api -X POST "repos/$GH_OWNER/$LIVE_REPO/actions/runners/registration-token" \
  --jq '{gh_runner_token: .token}' >"$tok" || {
  echo "runner-register: could not get a registration token (gh auth status?)" >&2
  exit 1
}
an_run ansible-playbook runner.yml -e "@$tok" || {
  echo "runner-register: runner.yml failed" >&2
  exit 1
}
rm -f "$tok"
if grep -qsE 'vars\.RUNNER_SSH_PUBLIC_KEY' .github/workflows/*.yml; then
  key="$(an_run ansible role_jump -b -m ansible.builtin.command -a "cat /home/gh-runner/.ssh/id_ed25519.pub" 2>/dev/null |
    grep -m1 -E '^(ssh-ed25519|ssh-rsa) ')" || {
    echo "runner-register: could not read gh-runner's public key on vm-$PREFIX-jump" >&2
    exit 1
  }
  gh variable set RUNNER_SSH_PUBLIC_KEY -R "$GH_OWNER/$LIVE_REPO" --body "$key" || {
    echo "runner-register: could not set the repo variable RUNNER_SSH_PUBLIC_KEY" >&2
    exit 1
  }
  echo "runner-register: RUNNER_SSH_PUBLIC_KEY = the new runner's public key (for the VMs Terraform builds next)"
fi
an_kv_prereqs || {
  echo "runner-register: the Key Vault prerequisites failed (az login?)" >&2
  exit 1
}
an_run ansible-playbook site.yml || {
  echo "runner-register: site.yml failed" >&2
  exit 1
}
if [[ -s "$held" ]]; then
  failed=""
  mapfile -t ids < <(sort -u "$held")
  for id in "${ids[@]}"; do
    # A run can only be re-run once its cancellation has completed.
    for _ in $(seq 1 60); do
      [[ "$(gh run view "$id" -R "$repo" --json status --jq .status || true)" == completed ]] && break
      sleep "${RUNNER_REGISTER_POLL_SECONDS:-5}"
    done
    if gh run rerun "$id" -R "$repo" >/dev/null; then
      echo "runner-register: re-ran ansible.yml run $id (triggered by the Terraform pipeline)"
    else
      failed+="$id"$'\n'
    fi
  done
  printf '%s' "$failed" >"$held"
  [[ -s "$held" ]] || rm -f "$held"
  if [[ -n "$failed" ]]; then
    echo "runner-register: could not re-run ansible.yml run(s) $(paste -sd' ' "$held"): gh run rerun <id> -R $repo, or run this script again" >&2
    exit 1
  fi
fi
echo "runner-register: vm-$PREFIX-jump is the self-hosted runner again, its key authorized on the fleet"
