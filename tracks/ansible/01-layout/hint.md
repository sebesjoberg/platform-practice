# an-01 hints

Docs:
- Collection requirements files and install paths: https://docs.ansible.com/ansible/latest/collections_guide/collections_installing.html
- `ansible.cfg` settings (`collections_path`, `roles_path`, `interpreter_python`): https://docs.ansible.com/ansible/latest/reference_appendices/config.html
- Where Ansible looks for its config, and the world-writable directory rule: https://docs.ansible.com/ansible/latest/reference_appendices/config.html#the-configuration-file
- Python requirements of `azure.azcollection`: https://docs.ansible.com/ansible/latest/collections/azure/azcollection/docsite/guide.html

Traps:
- **`ansible-core`, not `ansible`.** The `ansible` package bundles ~100 collections in versions
  you didn't choose. Pin `ansible-core` and list the collections you use.
- **The Azure collection's Python packages aren't installed with the collection.** They're in
  `collections/ansible_collections/azure/azcollection/requirements.txt` after the galaxy install;
  `pip install -r` that file into the venv. Without them the inventory plugin (an-02) fails with
  an import error. It's a big download (the Azure SDKs); do it once.
- **Install where Ansible looks.** `ansible-galaxy collection install -r ... -p collections` from
  `ansible/` installs into `ansible/collections/ansible_collections`, which is where
  `collections_path = ./collections` points (relative paths in `ansible.cfg` are relative to the
  file). Without `-p`, galaxy uses the first configured path, so it matters that the config is
  loaded at all.
- **Ansible may silently ignore `ansible.cfg`.** It only reads `./ansible.cfg` from the current
  directory, and not if that directory is world-writable (any `/mnt/c/...` path in WSL). Check the
  `config file =` line of `ansible --version`.
- **Editing a pin doesn't change what's installed.** Re-run the install after every pin change,
  with `--force` if galaxy reports "Nothing to do", and check `ansible-galaxy collection list`
  rather than assuming.
- **Older collections in `~/.ansible/collections`** (from other projects) are shadowed by the
  project path as long as `collections_path` lists only the project directory.
