# an-01 solution

## Approach

One directory, three pinned files, one gitignored venv. The latest 2.21 release of
`ansible-core` on 2026-11-23 is 2.21.6; the collection versions are the current Galaxy releases
(`ansible-galaxy collection list` / galaxy.ansible.com).

## Code

`ansible/requirements.txt`:

```text
ansible-core==2.21.6
```

`ansible/collections/requirements.yml`:

```yaml
---
collections:
  - name: azure.azcollection
    version: 4.2.0
  - name: community.general
    version: 14.0.1
  - name: ansible.posix
    version: 2.2.2
```

`ansible/ansible.cfg`:

```ini
[defaults]
collections_path = ./collections
roles_path = ./roles
interpreter_python = auto_silent
forks = 10
callback_result_format = yaml
```

`ansible/.gitignore`:

```text
.venv/
collections/ansible_collections/
.ansible/
*.retry
```

## Commands

```bash
cd "$LIVE_DIR" && git switch -c ansible-layout
mkdir -p ansible/collections && cd ansible
# write the four files above, then:
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml -p collections
pip install -r collections/ansible_collections/azure/azcollection/requirements.txt

ansible --version | head -3          # core 2.21.6, config file = .../ansible/ansible.cfg
ansible-galaxy collection list       # the three pins under .../ansible/collections/ansible_collections
git status --short                   # only the four new files: no .venv, no installed collections

cd .. && git add ansible && git commit -m "ansible: layout, pinned ansible-core and collections"
git push -u origin ansible-layout && gh pr create --fill && gh pr merge --squash --delete-branch
```

A colleague (or CI) rebuilds the identical toolchain with the same five commands. When a
collection needs an upgrade, the change is one line in `requirements.yml`, reviewed in a pull
request like any other.

## Verify

`./lab.sh grade`. No Azure resources are created; nothing to clean up.
