# an-16 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN16_REPO="$GH_OWNER/$LIVE_REPO"

# an16_triggers: pull_request, push to main, a schedule and workflow_dispatch with an input env.
an16_triggers() {
  local f=$AN_WF
  [[ -f "$f" ]] && grep -qE "^[[:space:]]+pull_request:" "$f" && grep -qE "^[[:space:]]+push:" "$f" &&
    grep -qE "^[[:space:]]+branches:.*main|^[[:space:]]+-[[:space:]]*.?main.?[[:space:]]*$" "$f" &&
    grep -qE "^[[:space:]]+schedule:" "$f" && grep -qE "^[[:space:]]*-[[:space:]]*cron:" "$f" &&
    grep -qE "^[[:space:]]+workflow_dispatch:" "$f" && grep -qE "^[[:space:]]+env:[[:space:]]*$" <(sed -n '/workflow_dispatch:/,/^[a-z]/p' "$f")
}

# an16_hosted_jobs: the jobs lint and molecule run on GitHub-hosted runners: ansible-lint and
# yamllint in lint, molecule test in molecule.
an16_hosted_jobs() {
  local j
  for j in lint molecule; do
    an_wf_job "$j" | grep -qE "runs-on:[[:space:]]*.?ubuntu-" || { echo "job $j is not on a GitHub-hosted runner"; return 1; }
  done
  an_wf_job lint | grep -qE "ansible-lint" && an_wf_job lint | grep -qE "yamllint" &&
    an_wf_job molecule | grep -qE "molecule test"
}

# an16_runner_jobs: check, apply and drift run on the self-hosted runner; every job there carries
# the fork guard, and none runs Molecule or Docker.
an16_runner_jobs() {
  local j
  for j in check apply drift; do
    an_wf_self_hosted "$j" || { echo "job $j does not run on [self-hosted, acme-jump]"; return 1; }
  done
  while IFS= read -r j; do
    an_wf_fork_guard "$j" || { echo "runner job $j has no fork guard in its if:"; return 1; }
    ! an_wf_job "$j" | grep -qE "molecule|docker" || { echo "runner job $j runs Molecule or Docker"; return 1; }
  done < <(an_wf_runner_jobs)
}

# an16_job_roles: check runs site.yml --check --diff, apply runs site.yml for real, drift runs
# bin/drift-check.sh and files issues labelled ansible-drift (issues: write).
an16_job_roles() {
  local c a d
  c="$(an_wf_job check)" a="$(an_wf_job apply)" d="$(an_wf_job drift)"
  grep -qE "site\.yml" <<<"$c" && grep -qE -- "--check|[[:space:]]-C([[:space:]]|$)" <<<"$c" && grep -qE -- "--diff|[[:space:]]-D([[:space:]]|$)" <<<"$c" &&
    grep -qE "ansible-playbook[^#]*site\.yml" <<<"$a" && ! grep -qE -- "--check" <<<"$a" &&
    grep -qE "drift-check\.sh" <<<"$d" && grep -qE "ansible-drift" <<<"$d" && grep -qE "issues:[[:space:]]*write" <<<"$d"
}

# an16_msi_no_secrets: the runner jobs authenticate with the VM's managed identity
# (ANSIBLE_AZURE_AUTH_SOURCE=msi for the inventory, acme_kv_auth_source=msi for Key Vault), and
# the workflow uses no repository secret.
an16_msi_no_secrets() {
  grep -qE "ANSIBLE_AZURE_AUTH_SOURCE:[[:space:]]*.?msi" "$AN_WF" && grep -qE "acme_kv_auth_source[=:][[:space:]]*.?msi" "$AN_WF" &&
    ! grep -vE "^[[:space:]]*#" "$AN_WF" | grep -qE "secrets\."
}

# an16_pr_check_or_catchup: a pull_request run had its check job succeed on the runner and a
# molecule job succeed; or (catchup never opens pull requests) the newest completed run on main
# is green and is catchup's own push.
an16_pr_check_or_catchup() {
  if an_wf_job_succeeded "$AN16_REPO" "event=pull_request" check 1 && an_wf_job_succeeded "$AN16_REPO" "event=pull_request" molecule 0; then
    return 0
  fi
  gh api "repos/$AN16_REPO/actions/workflows/ansible.yml/runs?status=completed&branch=main&per_page=1" \
    --jq '.workflow_runs[0] // {} | {conclusion, message: (.head_commit.message // "")}' |
    jq -e '.conclusion == "success" and (.message | startswith("catchup:"))' >/dev/null
}

# an16_only_tf_secrets: the repo's secrets (Actions, every environment's, Dependabot's) are only
# the Terraform track's two values, LEARNER_IP and BUDGET_EMAIL (tf-12, tf-25, tf-30), which are
# personal values masked in public logs, not credentials. Anything else fails: the runner needs
# no secret at all. Prints the names that aren't allowed.
an16_only_tf_secrets() {
  local names envs e extra
  names="$(gh api "repos/$AN16_REPO/actions/secrets?per_page=100" --jq '.secrets[].name')" || return 1
  names+=$'\n'"$(gh api "repos/$AN16_REPO/dependabot/secrets?per_page=100" --jq '.secrets[].name')" || return 1
  envs="$(gh api "repos/$AN16_REPO/environments?per_page=100" --jq '.environments[].name')" || return 1
  for e in $envs; do
    names+=$'\n'"$(gh api "repos/$AN16_REPO/environments/$e/secrets?per_page=100" --jq '.secrets[].name')" || return 1
  done
  extra="$(grep -vxE "LEARNER_IP|BUDGET_EMAIL|" <<<"$names" | sort -u)"
  [[ -z "$extra" ]] || { echo "secrets other than LEARNER_IP and BUDGET_EMAIL: $(paste -sd, - <<<"$extra")"; return 1; }
}
export -f an16_triggers an16_hosted_jobs an16_runner_jobs an16_job_roles an16_msi_no_secrets \
  an16_pr_check_or_catchup an16_only_tf_secrets

check_code "ansible.yml: pull_request, push to main, schedule, workflow_dispatch with input env" \
  'an16_triggers' \
  "write .github/workflows/ansible.yml with on: pull_request, push (branches: [main]), schedule (cron) and workflow_dispatch with an input env"

check_code "jobs lint (ansible-lint, yamllint) and molecule run on GitHub-hosted runners" \
  'an16_hosted_jobs' \
  "jobs lint (ansible-lint and yamllint) and molecule (molecule test, a matrix over the roles) with runs-on: ubuntu-latest: containers never run on the 1 GiB jump host"

check_code "jobs check, apply and drift run on [self-hosted, acme-jump]; every runner job has the fork guard; no Molecule there" \
  'an16_runner_jobs' \
  "runs-on: [self-hosted, acme-jump] for check, apply and drift, each with if: ... && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)"

check_code "check: site.yml --check --diff; apply: site.yml; drift: bin/drift-check.sh with an ansible-drift issue" \
  'an16_job_roles' \
  "check runs ansible-playbook site.yml --check --diff (pull requests), apply runs ansible-playbook site.yml (push to main), drift runs bin/drift-check.sh and opens or updates an issue labelled ansible-drift (permissions: issues: write)"

check_code "the runner jobs use the VM's managed identity (msi), and the workflow uses no secrets" \
  'an16_msi_no_secrets' \
  "env ANSIBLE_AZURE_AUTH_SOURCE: msi (inventory) and -e acme_kv_auth_source=msi (Key Vault) on the runner jobs; no secrets.* anywhere in ansible.yml"

check "workflow ansible.yml is active on GitHub" \
  '[[ "$(gh api "repos/$AN16_REPO/actions/workflows/ansible.yml" --jq .state)" == active ]]' \
  "no active workflow ansible.yml in $AN16_REPO (merged to main?)"

check "a push to main applied the fleet: job apply succeeded on the self-hosted runner" \
  'an_wf_job_succeeded "$AN16_REPO" "branch=main" apply 1' \
  "merge an Ansible change (or gh workflow run ansible.yml -f env=dev) and let job apply finish on vm-$PREFIX-jump (runner online? gh api repos/$AN16_REPO/actions/runners)"

check "a pull request ran check (on the runner) and molecule green" \
  'an16_pr_check_or_catchup' \
  "open a pull request that changes ansible/: its check job (site.yml --check --diff on the runner) and the molecule jobs must succeed"

check "a drift check ran green on the runner (schedule, or gh workflow run ansible.yml -f task=drift)" \
  'an_wf_job_succeeded "$AN16_REPO" "branch=main" drift 1' \
  "gh workflow run ansible.yml -f task=drift: the drift job must succeed (no drift); with drift it fails and opens an issue labelled ansible-drift"

check "the repo has no secrets besides the Terraform track's LEARNER_IP and BUDGET_EMAIL (Actions, environments, Dependabot)" \
  'an16_only_tf_secrets' \
  "gh secret list -R $AN16_REPO (and --env <name>, --app dependabot): the runner authenticates with the jump host's managed identity and its own SSH key; delete every secret other than LEARNER_IP and BUDGET_EMAIL"
