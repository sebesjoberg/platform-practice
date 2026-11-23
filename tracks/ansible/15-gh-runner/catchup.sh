#!/usr/bin/env bash
# an-15 catchup (after-push, cwd = LIVE_DIR), as you (gh, your inventory):
#   - the release tag acme.platform-1.1.0 (normally already made by an-01's hook)
#   - fork pull requests from every outside contributor need approval (a public repo with a
#     self-hosted runner)
#   - runner.yml with a fresh registration token (handed over in a 0600 file, removed afterwards),
#     then site.yml once more, so that role base authorizes the runner's new SSH key everywhere
# Idempotent: a registered runner keeps its registration (the token is then unused).
set -euo pipefail
[[ "${CATCHUP_PHASE:-after-push}" == after-push ]] || exit 0

here="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "$here/../lib/ansible.sh"
# shellcheck source=/dev/null
source "$here/../lib/collection-tag.sh"
repo="${GH_OWNER:?}/${LIVE_REPO:?}"

an_collection_tag acme.platform-1.1.0
gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" \
  -f approval_policy=all_external_contributors >/dev/null
echo "an-15: fork pull requests from outside contributors need approval in $repo"

tok="$(mktemp)"
trap 'rm -f "$tok"' EXIT
chmod 600 "$tok"
gh api -X POST "repos/$repo/actions/runners/registration-token" --jq '{gh_runner_token: .token}' >"$tok"
an_run ansible-playbook runner.yml -e "@$tok"
rm -f "$tok"
an_run ansible-playbook site.yml
echo "an-15: vm-$PREFIX-jump is the self-hosted runner of $repo, its key authorized on the fleet"
