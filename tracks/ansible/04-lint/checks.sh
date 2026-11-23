# an-04 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an04_precommit [args...]: pre-commit from the venv, with the repo's config, from the repo root.
an04_precommit() {
  local cfg
  cfg="$(an_precommit_config)" || return 1
  [[ -x ansible/.venv/bin/pre-commit ]] || return 3
  ansible/.venv/bin/pre-commit "$@" --config "$cfg"
}
export -f an04_precommit

check_code "an ansible-lint config selects the production profile" \
  'f="$(an_first_file ansible/.ansible-lint ansible/.ansible-lint.yml ansible/.ansible-lint.yaml ansible/.config/ansible-lint.yml ansible/.config/ansible-lint.yaml .ansible-lint .config/ansible-lint.yml)" && grep -qE "^profile:[[:space:]]*.?production.?[[:space:]]*(#.*)?$" "$f"' \
  "add ansible/.ansible-lint with profile: production"

check_code "a yamllint config for the Ansible code" \
  'an_first_file ansible/.yamllint ansible/.yamllint.yml ansible/.yamllint.yaml .yamllint .yamllint.yml .yamllint.yaml >/dev/null' \
  "add ansible/.yamllint (extends: default, with the settings ansible-lint requires of a custom yamllint config)"

check_code "the pre-commit config runs ansible-lint and yamllint, every repo pinned to a release" \
  'f="$(an_precommit_config)" && grep -qE "repo:[[:space:]]*.?https://github\.com/ansible/ansible-lint" "$f" && grep -qE "repo:[[:space:]]*.?https://github\.com/adrienverge/yamllint" "$f" && grep -qE "id:[[:space:]]*.?ansible-lint" "$f" && grep -qE "id:[[:space:]]*.?yamllint" "$f" && [[ "$(grep -cE "^[[:space:]]*(-[[:space:]]*)?repo:[[:space:]]*.?https?://" "$f")" -le "$(grep -cE "^[[:space:]]*rev:[[:space:]]*.?(v?[0-9]+\.[0-9]+(\.[0-9]+)?|[0-9a-f]{40}).?[[:space:]]*(#.*)?$" "$f")" ]]' \
  "add ansible/.pre-commit-config.yaml with the repos https://github.com/ansible/ansible-lint (hook ansible-lint) and https://github.com/adrienverge/yamllint (hook yamllint), each with rev: a release tag (or a commit SHA), never a branch"

check_code "ansible/requirements.txt pins ansible-lint, yamllint and pre-commit" \
  'f=ansible/requirements.txt && grep -qE "^ansible-lint==[0-9]" "$f" && grep -qE "^yamllint==[0-9]" "$f" && grep -qE "^pre-commit==[0-9]" "$f"' \
  "pin the linters in ansible/requirements.txt (ansible-lint==..., yamllint==..., pre-commit==...), the same versions as the hooks, and pip install -r it into ansible/.venv"

an04_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=300
check "ansible-lint passes with the production profile" \
  'an_run ansible-lint' \
  "cd ansible && ansible-lint (from the venv) must pass: fix each finding, or skip a rule for one line with a # noqa: <rule> comment that says why"

check "pre-commit run --all-files passes" \
  'an04_precommit run --all-files' \
  "from the repo root: ansible/.venv/bin/pre-commit run --config ansible/.pre-commit-config.yaml --all-files must pass (the first run installs the hook environments)"
GRADE_TIMEOUT="$an04_timeout"

check "the pre-commit git hook is installed" \
  'h=.git/hooks/pre-commit && [[ -x "$h" ]] && grep -q "pre-commit" "$h"' \
  "pre-commit install --config ansible/.pre-commit-config.yaml (from the repo root, venv active) so the hooks run on every commit"
