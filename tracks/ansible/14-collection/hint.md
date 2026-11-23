# an-14 hints

Docs:
- Collection structure, `galaxy.yml`, `meta/runtime.yml`: https://docs.ansible.com/ansible/latest/dev_guide/developing_collections_structure.html
- Installing from git, with a subdirectory and a tag: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html#installing-a-collection-from-a-git-repository
- Using roles and modules from a collection (FQCN): https://docs.ansible.com/ansible/latest/collections_guide/collections_using_playbooks.html
- `build_ignore` and `manifest`: https://docs.ansible.com/ansible/latest/dev_guide/developing_collections_distributing.html#ignoring-files-and-folders

Traps:
- **Why `collections_src/ansible_collections/acme/platform`** and not just `collections_src/acme`?
  Ansible only finds collections at `<path>/ansible_collections/<namespace>/<name>`. With that
  layout, Molecule (and you, while developing) can put `collections_src` on
  `ANSIBLE_COLLECTIONS_PATH` and test the source as `acme.platform.*`, while `site.yml` uses the
  release installed in `ansible/collections`.
- **The git source syntax:** `name: https://github.com/{{GH_OWNER}}/{{LIVE_REPO}}.git#/<subdir>`,
  `type: git`, `version: <tag>`. galaxy clones the repo, checks out the tag and builds the
  collection from the subdirectory. The tag must be pushed before anything installs it, CI
  included.
- **A pin change needs `--force`:** galaxy keeps an installed `acme.platform` when you bump the
  tag. `ansible-galaxy collection install -r collections/requirements.yml -p collections --force`.
- **Molecule:** the scenarios move with the roles, and three things in them change: the paths in
  `molecule.yml`'s `env` (count the `..`), `converge.yml` applies `acme.platform.<role>`, and
  `app_env` calls `acme.platform.acme_app_setting`. `ANSIBLE_LIBRARY` is no longer needed.
- **ansible-lint lints the collection's metadata**: `galaxy.yml` needs a version ≥ 1.0.0, a
  required tag (`infrastructure`, `linux`, ...) and a changelog next to it, and `meta/runtime.yml`
  a `requires_ansible` that ansible-lint knows as supported.
- **A role's own files stay relative to the role**: `role_path`, `files/`, `templates/` work the
  same inside a collection. Only names change.
- **The tag is a release:** never move it. A fix is `1.0.1`, with a `CHANGELOG.md` line.
- **`git mv`** keeps the history of every role file. Don't copy and delete.
