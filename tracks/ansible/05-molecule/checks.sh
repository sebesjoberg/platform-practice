# an-05 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an05_molecule_test: molecule test for role base, from the role directory with the venv active.
an05_molecule_test() {
  local venv="$PWD/ansible/.venv" d
  [[ -f "$venv/bin/activate" ]] || return 3
  d="$(an_role_dir base)" && [[ -n "$d" ]] || return 1
  (
    cd "$d" || exit 1
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0 PY_COLORS=0
    molecule test
  )
}
export -f an05_molecule_test

check_code "roles/base/molecule/default: docker driver, converge, idempotence and the ansible verifier kept" \
  'd="$(an_role_dir base)/molecule/default" && f=$d/molecule.yml && grep -qE "^driver:" "$f" && grep -qE "^[[:space:]]+name:[[:space:]]*.?docker.?[[:space:]]*$" "$f" && compgen -G "$d/converge.y*ml" >/dev/null && ! grep -qE "^[[:space:]]+name:[[:space:]]*.?testinfra" "$f" && { ! grep -qE "^[[:space:]]*test_sequence:" "$f" || { grep -qE "^[[:space:]]*-[[:space:]]*idempotence" "$f" && grep -qE "^[[:space:]]*-[[:space:]]*verify" "$f"; }; }' \
  "create ansible/roles/base/molecule/default with molecule.yml (driver: name: docker, verifier: ansible) and converge.yml; a custom test_sequence must keep idempotence and verify"

check_code "verify.yml asserts the sshd drop-in and the packages" \
  'v="$(an_first_file "$(an_role_dir base)"/molecule/default/verify.y*ml)" && [[ -n "$v" ]] && grep -qE "assert" "$v" && grep -qE "sshd_config\.d|sshd -T" "$v" && grep -qE "package_facts|dpkg|apt list|packages" "$v"' \
  "write ansible/roles/base/molecule/default/verify.yml: assertions (ansible.builtin.assert) on the sshd drop-in's content and on the installed packages"

check_code "community.docker and Molecule are pinned" \
  'an_collection_pinned ansible/collections/requirements.yml community.docker && grep -qE "^molecule==[0-9]" ansible/requirements.txt && grep -qE "^molecule-plugins(\[docker\])?==[0-9]" ansible/requirements.txt' \
  "pin community.docker (exact version) in ansible/collections/requirements.yml, and molecule==... and molecule-plugins[docker]==... in ansible/requirements.txt"

an05_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=900
check "molecule test passes for role base (converge, idempotence, verify)" \
  'an05_molecule_test' \
  "cd ansible/roles/base && molecule test (venv active, Docker Desktop running) must pass: converge, a second converge with changed=0, verify"
GRADE_TIMEOUT="$an05_timeout"
