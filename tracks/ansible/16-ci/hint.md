# an-16 hints

Docs:
- Choosing self-hosted runners (`runs-on` with labels): https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/using-self-hosted-runners-in-a-workflow
- Events and their contexts (`github.event.pull_request.head.repo.full_name`): https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows
- `workflow_dispatch` inputs: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onworkflow_dispatchinputs
- The `azure_rm` inventory's `auth_source` (and its environment variable): https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_rm_inventory.html

Traps:
- **The runner can't use your connection settings.** The jump host's public IP is closed to the
  jump host itself (the NSG allows SSH from your IP only), there is no `~/.ssh/{{PREFIX}}_lab` on
  it, and a ProxyCommand through itself makes no sense. Extra variables (`-e @ci/runner.yml`) beat
  everything in the inventory and are templated per host:
  `ansible_host: "{{ private_ipv4_addresses | first }}"`, `ansible_user: ops`, the runner's key,
  and a switch that turns off the jump hop in `group_vars/role_web.yml`.
- **`base` manages `ops`' keys exclusively.** If CI computed a different key list than your
  laptop, every run would flip it. On the runner the lab key's public half comes from the repo
  variable `SSH_PUBLIC_KEY` (tf-25): `lookup('ansible.builtin.env', 'SSH_PUBLIC_KEY')`.
- **`auth_source: cli` in the inventory file stays.** The plugin reads
  `ANSIBLE_AZURE_AUTH_SOURCE` first; set it to `msi` in the runner jobs' `env`, with
  `AZURE_SUBSCRIPTION_ID` from the repo variable so it doesn't have to guess.
- **The fork guard is per job**, combined with the job's own condition:
  `if: github.event_name == 'pull_request' && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository)`.
  A fork's code on your runner would have root on the fleet.
- **`--check` exits 0 with drift**, `drift-check.sh` (an-12) exits 2: capture its exit code in a
  step output (`rc=0; bin/drift-check.sh ... || rc=$?`) and decide in later steps; tf-27's
  `drift.yml` has the issue logic to borrow. `gh` is on the runner (role `gh_runner`).
- **Build the toolchain once:** a venv keyed by a hash of `requirements.txt` and
  `collections/requirements.yml`, under the runner user's home; only `ansible-core`, the
  collections and the Azure SDK (no linters, no Molecule). A venv can't be moved after it's built.
  `ANSIBLE_COLLECTIONS_PATH` beats `ansible.cfg`'s `collections_path`.
- **The collection must be installable in CI**: lint and Molecule install
  `collections/requirements.yml`, including `acme.platform` by tag. A PR that pins a tag you
  haven't pushed fails there, which is the point.
- **Terraform's pipeline ignores this**: since tf-24 an Ansible-only change skips its apply jobs.
