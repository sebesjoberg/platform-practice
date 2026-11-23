# an-01 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

check_code "ansible/requirements.txt pins ansible-core 2.21.x exactly" \
  'grep -qE "^ansible-core[[:space:]]*==[[:space:]]*2\.21\.[0-9]+[[:space:]]*(#.*)?$" ansible/requirements.txt' \
  "ansible/requirements.txt needs a line ansible-core==2.21.<patch> (2.22 needs Python 3.13; WSL Ubuntu 24.04 has 3.12)"

check_code "ansible/collections/requirements.yml pins azure.azcollection, community.general and ansible.posix by exact version" \
  'f=ansible/collections/requirements.yml && [[ -f "$f" ]] && for c in azure.azcollection community.general ansible.posix; do an_collection_pinned "$f" "$c" || exit 1; done' \
  "list azure.azcollection, community.general and ansible.posix under collections: in ansible/collections/requirements.yml, each with version: X.Y.Z (an exact version, no range)"

check_code "ansible/ansible.cfg keeps collections and roles inside the project" \
  'grep -qE "^[[:space:]]*\[defaults\]" ansible/ansible.cfg && grep -qE "^[[:space:]]*collections_paths?[[:space:]]*=[[:space:]]*\S" ansible/ansible.cfg && grep -qE "^[[:space:]]*roles_path[[:space:]]*=[[:space:]]*\S" ansible/ansible.cfg' \
  "ansible/ansible.cfg needs a [defaults] section with collections_path and roles_path pointing into ansible/ (./collections, ./roles)"

check_code "the venv and the installed collections are gitignored" \
  'grep -qsxE "[[:space:]]*/?(ansible/)?\.venv/?[[:space:]]*" ansible/.gitignore .gitignore && grep -qsE "^[[:space:]]*/?(ansible/)?collections/ansible_collections/?" ansible/.gitignore .gitignore' \
  "ignore .venv/ and collections/ansible_collections/ in ansible/.gitignore: both are rebuilt from the pinned files and never committed"

check "ansible/.venv runs ansible-core 2.21 and the Azure collection's Python packages" \
  'an_run ansible --version | grep -qE "core 2\.21\." && an_run python3 -c "import azure.identity, azure.mgmt.compute, azure.cli.core"' \
  "create the venv: cd ansible && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt, then the collections, then .venv/bin/pip install -r collections/ansible_collections/azure/azcollection/requirements.txt"

check "the collections are installed in exactly the pinned versions" \
  'an_collections_match' \
  "cd ansible && .venv/bin/ansible-galaxy collection install -r collections/requirements.yml -p collections (add --force after changing a pin); ansible-galaxy collection list shows what Ansible resolves"
