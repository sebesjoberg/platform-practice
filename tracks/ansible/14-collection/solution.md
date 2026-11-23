# an-14 solution

## Approach

Move the roles and the module into a collection directory inside the repo, give it metadata,
release it with a tag, and make `requirements.yml` install that tag from git like any other
collection. The repo's playbooks then use the release (FQCNs), and the Molecule scenarios test
the source (collections path pointing at `collections_src`).

## Code

Layout:

```text
ansible/collections_src/ansible_collections/acme/platform/
  galaxy.yml  meta/runtime.yml  README.md  CHANGELOG.md
  plugins/modules/acme_app_setting.py
  roles/{base,app_env,acme_hello,nginx,haproxy}/   (with their molecule/ scenarios)
```

`galaxy.yml`:

```yaml
---
namespace: acme
name: platform
version: 1.0.0
readme: README.md
authors:
  - Acme platform team
description: Acme's platform roles (baseline, app, web, load balancer) and the acme_app_setting module
license:
  - GPL-3.0-or-later
tags:
  - infrastructure
  - linux
repository: https://github.com/{{GH_OWNER}}/{{LIVE_REPO}}
dependencies:
  community.general: ">=14.0.0"
  ansible.posix: ">=2.2.0"
build_ignore:
  - "roles/*/molecule"
  - ".ansible"
  - "*.tar.gz"
```

`meta/runtime.yml`: `requires_ansible: ">=2.19.0"`. `CHANGELOG.md` with a `1.0.0` entry.

`ansible/collections/requirements.yml`, added:

```yaml
  - name: https://github.com/{{GH_OWNER}}/{{LIVE_REPO}}.git#/ansible/collections_src/ansible_collections/acme/platform
    type: git
    version: acme.platform-1.0.0
```

`site.yml` and `rolling.yml`: `role: acme.platform.base` (and `app_env`, `acme_hello`, `nginx`,
`haproxy`). `roles/app_env/tasks/main.yml`: `acme.platform.acme_app_setting:`. The module's
`EXAMPLES` use the FQCN too. `ansible.cfg`: the `library` line goes.

Each `roles/<role>/molecule/default/molecule.yml`:

```yaml
ansible:
  env:
    ANSIBLE_COLLECTIONS_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../../../../..:\
      ${MOLECULE_PROJECT_DIRECTORY}/../../../../../../collections:\
      ${ANSIBLE_COLLECTIONS_PATH:-~/.ansible/collections}"
```

and `converge.yml` applies `role: acme.platform.<role>`.

## Commands

```bash
cd "$LIVE_DIR" && git switch -c collection
C=ansible/collections_src/ansible_collections/acme/platform
mkdir -p "$C/roles" "$C/plugins/modules" "$C/meta"
for r in base app_env acme_hello nginx haproxy; do git mv "ansible/roles/$r" "$C/roles/$r"; done
git mv ansible/library/acme_app_setting.py "$C/plugins/modules/"
# write galaxy.yml, meta/runtime.yml, README.md, CHANGELOG.md; edit FQCNs and molecule.yml paths
cd ansible && source .venv/bin/activate
(cd collections_src/ansible_collections/acme/platform/roles/app_env && molecule test)
ansible-lint

# the release: merge first, then tag the merge commit on main
cd .. && git add -A && git commit -m "ansible: roles and module as collection acme.platform 1.0.0"
git push -u origin collection && gh pr create --fill && gh pr merge --squash --delete-branch
git switch main && git pull
git tag -a acme.platform-1.0.0 -m "acme.platform 1.0.0" && git push origin acme.platform-1.0.0

# consume it: pin the tag (a second small PR, or in the first one if you tag its head commit)
cd ansible
ansible-galaxy collection install -r collections/requirements.yml -p collections --force
ansible-galaxy collection list acme.platform
ansible-doc acme.platform.acme_app_setting | head -5
ansible-playbook site.yml          # changed=0
```

## Verify

`./lab.sh grade`: the layout, the pin, the tag on GitHub (its `galaxy.yml` version must match the
tag), the installed version, `molecule test` for `app_env` from the collection, and a second
`site.yml` run.
