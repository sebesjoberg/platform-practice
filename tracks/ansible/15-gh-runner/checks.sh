# an-15 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN15_REPO="$GH_OWNER/$LIVE_REPO"

# an15_role: role gh_runner registers with config.sh (labels, a token variable, no_log) and gives
# the runner's user its own ed25519 key.
an15_role() {
  local r
  r="$(an_role_dir gh_runner)" && [[ -n "$r" ]] || return 1
  grep -rqsE "config\.sh" "$r/tasks" && grep -rqsE -- "--labels" "$r/tasks" &&
    grep -rqsE -- "--token" "$r/tasks" && grep -rqsE "no_log:[[:space:]]*.?true" "$r/tasks" &&
    grep -rqsE "acme-jump" "$r" ansible/inventory &&
    grep -rqsE "ed25519" "$r/tasks" "$r/defaults" && grep -rqsE "generate_ssh_key|ssh-keygen|openssh_keypair" "$r/tasks"
}

# an15_released: the collection's version is the pinned release, and that release has gh_runner.
an15_released() {
  local d tag
  d="$(an_coll_dir)" && tag="$(an_coll_pin)" || return 1
  [[ -d "$d/roles/gh_runner" ]] || return 1
  grep -qE "^version:[[:space:]]*.?${tag#acme.platform-}.?[[:space:]]*(#.*)?$" "$d/galaxy.yml"
}

# an15_base_gets_runner_key: a playbook reads the runner's public key on the jump host (slurp,
# delegated to role_jump), so that role base can authorize it.
an15_base_gets_runner_key() {
  local f
  while IFS= read -r f; do
    grep -qE "^[[:space:]]*(-[[:space:]]+)?(ansible\.builtin\.)?slurp:" "$f" || continue
    an_delegates_to "$f" role_jump && return 0
  done < <(an_playbooks)
  return 1
}

# an15_no_token_in_repo: nothing in ansible/ or .github/ looks like a runner registration token
# (29 characters, A-Z and 0-9, starting with A).
an15_no_token_in_repo() {
  ! grep -rqsE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible \
    "(^|[^A-Za-z0-9])A[A-Z0-9]{28}([^A-Za-z0-9]|$)" ansible .github
}

# an15_runner_online: GitHub lists the runner vm-<prefix>-jump online with self-hosted and
# acme-jump.
an15_runner_online() {
  gh api "repos/$AN15_REPO/actions/runners" --jq ".runners[] | select(.name == \"vm-$PREFIX-jump\")" |
    jq -se 'length == 1 and .[0].status == "online" and ([.[0].labels[].name] | index("self-hosted") != null and index("acme-jump") != null)' >/dev/null
}

# an15_runner_on_vm: the probe on the jump host, with both web VMs' private IPs.
an15_runner_on_vm() {
  local -a ips
  mapfile -t ips < <(an_group_ips role_web)
  [[ ${#ips[@]} -ge 2 ]] || return 1
  an_probe role_jump 1 runner.sh "${ips[*]}"
}
export -f an15_role an15_released an15_base_gets_runner_key an15_no_token_in_repo an15_runner_online an15_runner_on_vm

check_code "role gh_runner: registers with config.sh (labels incl. acme-jump, token with no_log), own ed25519 key" \
  'an15_role' \
  "add role gh_runner to the collection: user gh-runner with generate_ssh_key (ed25519), the runner unpacked, ./config.sh --unattended --url ... --token \"{{ gh_runner_token }}\" --labels acme-jump with no_log: true, svc.sh install"

check_code "role gh_runner has a Molecule scenario (docker, converge, verify, idempotence kept)" \
  'an_molecule_scenario gh_runner' \
  "create roles/gh_runner/molecule/default; converge.yml switches registration off (nothing to register with in a container)"

check_code "runner.yml applies role gh_runner to role_jump" \
  'an_play_applies role_jump gh_runner' \
  "write ansible/runner.yml: hosts: role_jump, become: true, roles: [acme.platform.gh_runner] (not in site.yml: CI must not reconfigure its own runner)"

check_code "the pinned collection release is the source's version and contains gh_runner" \
  'an15_released' \
  "bump galaxy.yml to 1.1.0 (CHANGELOG.md entry), merge, tag acme.platform-1.1.0, push the tag, pin it in collections/requirements.yml"

check_code "site.yml reads the runner's public key on the jump host (slurp delegated to role_jump) for role base" \
  'an15_base_gets_runner_key' \
  "in site.yml's baseline play: a pre_task that slurps /home/gh-runner/.ssh/id_ed25519.pub with delegate_to: \"{{ groups['role_jump'] | first }}\" and run_once, and base_ops_authorized_keys that adds it when it exists"

check_code "no runner registration token in the repo" \
  'an15_no_token_in_repo' \
  "a registration token is a secret (and expires in an hour): pass it with -e @<file outside the repo>, never commit it"

check "GitHub lists the runner vm-$PREFIX-jump online, with the labels self-hosted and acme-jump" \
  'an15_runner_online' \
  "gh api repos/$AN15_REPO/actions/runners must show vm-$PREFIX-jump online with self-hosted and acme-jump: run runner.yml with a fresh token (gh api -X POST repos/$AN15_REPO/actions/runners/registration-token)"

check "fork pull requests from every outside contributor need approval before workflows run" \
  '[[ "$(gh api "repos/$AN15_REPO/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy)" == all_external_contributors ]]' \
  "gh api -X PUT repos/$AN15_REPO/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors (a public repo with a self-hosted runner)"

an15_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "on the jump host: the runner service runs as gh-runner, whose own key logs in as ops on both web VMs" \
  'an15_runner_on_vm' \
  "systemctl status 'actions.runner.*' on the jump host must be active as gh-runner; sudo -u gh-runner ssh -i ~gh-runner/.ssh/id_ed25519 ops@<web private IP> true must work (run site.yml after runner.yml)"

GRADE_TIMEOUT=900
check "molecule test passes for role gh_runner" \
  'an_molecule_test gh_runner' \
  "cd ansible/collections_src/ansible_collections/acme/platform/roles/gh_runner && molecule test (venv active, Docker running)"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: with the runner's key authorized, the second run changes nothing"
GRADE_TIMEOUT="$an15_timeout"
