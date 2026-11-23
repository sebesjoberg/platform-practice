# shellcheck shell=bash
# Run the live repo's ansible.yml from catchup and wait for it (an-16, an-20). Sourced by their
# catchup.sh. Needs gh; reuses the Terraform track's run helpers (ci_new_run, ci_wait_run).

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../terraform/lib/ci-dispatch.sh"

# an_ci_dispatch_wait <tag> <field=value>...: dispatch ansible.yml on main with those inputs
# (gh workflow run -f ...) and wait for that run; up to 2 attempts. 0 = success.
an_ci_dispatch_wait() {
  local tag=$1 repo="${GH_OWNER:?}/${LIVE_REPO:?}" attempt known id f
  shift
  local -a fields=()
  for f in "$@"; do fields+=(-f "$f"); done
  for attempt in 1 2; do
    known=" $(gh run list -R "$repo" --workflow ansible.yml --event workflow_dispatch --limit 20 --json databaseId --jq '.[].databaseId' | tr '\n' ' ') "
    gh workflow run ansible.yml -R "$repo" --ref main "${fields[@]}"
    id=""
    for _ in $(seq 1 30); do
      id="$(ci_new_run "$repo" "$known" ansible.yml)"
      [[ -n "$id" ]] && break
      sleep "${CI_POLL_SECONDS:-5}"
    done
    [[ -n "$id" ]] || { echo "$tag: could not find the dispatched ansible.yml run" >&2; return 1; }
    echo "$tag: waiting for ansible.yml run $id ($*)"
    if ci_wait_run "$repo" "$id"; then
      echo "$tag: run $id succeeded"
      return 0
    fi
    echo "$tag: run $id failed (attempt $attempt/2)" >&2
    sleep "${CI_RETRY_SECONDS:-60}"
  done
  echo "$tag: ansible.yml keeps failing; see gh run list -R $repo --workflow ansible.yml" >&2
  return 1
}
