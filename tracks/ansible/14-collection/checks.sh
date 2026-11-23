# an-14 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN14_ROLES="base app_env acme_hello nginx haproxy"

# an14_metadata: galaxy.yml with a semantic version and Molecule kept out of the build, and
# meta/runtime.yml with requires_ansible.
an14_metadata() {
  local d
  d="$(an_coll_dir)" || return 1
  grep -qE "^version:[[:space:]]*.?[0-9]+\.[0-9]+\.[0-9]+.?[[:space:]]*(#.*)?$" "$d/galaxy.yml" &&
    grep -qE "^build_ignore:" "$d/galaxy.yml" && grep -qE "molecule" "$d/galaxy.yml" &&
    grep -qsE "^requires_ansible:" "$d/meta/runtime.yml"
}

# an14_content: the five roles and the module live in the collection, and nowhere else.
an14_content() {
  local d r
  d="$(an_coll_dir)" || return 1
  for r in $AN14_ROLES; do
    [[ -d "$d/roles/$r/tasks" ]] || { echo "no role $r in $d/roles"; return 1; }
    [[ ! -d "ansible/roles/$r" ]] || { echo "ansible/roles/$r is still there"; return 1; }
  done
  [[ -f "$d/plugins/modules/acme_app_setting.py" ]] || { echo "no plugins/modules/acme_app_setting.py in $d"; return 1; }
  [[ ! -f ansible/library/acme_app_setting.py ]] || { echo "ansible/library/acme_app_setting.py is still there"; return 1; }
}

# an14_playbooks_fqcn: site.yml applies the roles by FQCN, and no playbook still names one of them
# by its bare name (it would no longer resolve).
an14_playbooks_fqcn() {
  local f r
  grep -qE "acme\.platform\.base" ansible/site.yml || return 1
  while IFS= read -r f; do
    for r in $AN14_ROLES; do
      if grep -qE "^[[:space:]]*(-[[:space:]]+)?(role|name):[[:space:]]*.?$r.?[[:space:]]*$" "$f"; then
        echo "$f still uses role $r by its bare name"
        return 1
      fi
    done
  done < <(an_playbooks)
}

# an14_tag_on_github: the pinned tag exists on GitHub and its galaxy.yml has the tag's version.
an14_tag_on_github() {
  local tag d v
  tag="$(an_coll_pin)" && d="$(an_coll_dir)" || return 1
  v="$(gh api "repos/$GH_OWNER/$LIVE_REPO/contents/$d/galaxy.yml?ref=$tag" --jq .content | base64 -d |
    sed -nE "s/^version:[[:space:]]*[\"']?([0-9.]+).*/\1/p")" || return 1
  [[ "$tag" == "acme.platform-$v" ]] || { echo "tag $tag holds galaxy.yml version ${v:-?}"; return 1; }
}

# an14_installed: ansible-galaxy (with the repo's ansible.cfg) resolves acme.platform to the
# pinned version, installed under ansible/collections.
an14_installed() {
  local tag
  tag="$(an_coll_pin)" || return 1
  an_run ansible-galaxy collection list acme.platform --format json 2>/dev/null |
    jq -e --arg v "${tag#acme.platform-}" 'to_entries | map(select(.key | test("/ansible/collections/ansible_collections$"))) | .[0].value["acme.platform"].version == $v' >/dev/null
}
export -f an14_metadata an14_content an14_playbooks_fqcn an14_tag_on_github an14_installed

check_code "collection acme.platform: galaxy.yml (semver, Molecule in build_ignore) and meta/runtime.yml" \
  'an14_metadata' \
  "create ansible/collections_src/ansible_collections/acme/platform/galaxy.yml (namespace: acme, name: platform, version: 1.0.0, dependencies, build_ignore with roles/*/molecule) and meta/runtime.yml (requires_ansible)"

check_code "the five roles and the module live in the collection, and only there" \
  'an14_content' \
  "git mv ansible/roles/<role> to the collection's roles/ (base, app_env, acme_hello, nginx, haproxy) and ansible/library/acme_app_setting.py to its plugins/modules/"

check_code "requirements.yml installs acme.platform from this repo by git tag (#/ subdirectory, type git, acme.platform-X.Y.Z)" \
  'an_coll_pin >/dev/null' \
  "add to ansible/collections/requirements.yml: name: https://github.com/$GH_OWNER/$LIVE_REPO.git#/<path of the collection>, type: git, version: acme.platform-1.0.0"

check_code "the playbooks apply the roles by FQCN (acme.platform.<role>)" \
  'an14_playbooks_fqcn' \
  "site.yml and rolling.yml: role: acme.platform.base, acme.platform.app_env, ... (the bare names no longer resolve)"

check "the pinned tag exists on GitHub and holds the collection at that version" \
  'an14_tag_on_github' \
  "git tag acme.platform-1.0.0 <a commit of main with the collection> && git push origin acme.platform-1.0.0; its galaxy.yml must say version: 1.0.0"

check "ansible-galaxy resolves acme.platform to the pinned version, installed in ansible/collections" \
  'an14_installed' \
  "cd ansible && ansible-galaxy collection install -r collections/requirements.yml -p collections --force, then ansible-galaxy collection list acme.platform"

an14_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=900
check "molecule test passes for role app_env in the collection (the module by its FQCN)" \
  'an_molecule_test app_env' \
  "cd ansible/collections_src/ansible_collections/acme/platform/roles/app_env && molecule test: the scenario's ANSIBLE_COLLECTIONS_PATH must reach the collection source"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the roles from the installed release must leave the fleet as it was"
GRADE_TIMEOUT="$an14_timeout"
