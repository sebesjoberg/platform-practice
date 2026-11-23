# an-19 hints

Docs:
- Several inventory sources, and a static YAML inventory: https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#using-multiple-inventory-sources
- Patterns (`env_dev:env_hub`, `role_web:&env_dev`): https://docs.ansible.com/ansible/latest/inventory_guide/intro_patterns.html
- `assert`, `any_errors_fatal`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html#aborting-a-play-on-all-hosts
- GitHub environments and required reviewers: https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment

Traps:
- **A keyed group only exists when a host has the key.** `keyed_groups` makes `env_prod` from a VM
  tagged `env=prod`; with no such VM there is no group, and `--limit env_prod` or `hosts:
  env_prod` errors out or warns. A static file (`all: children: env_prod:`) declares it empty;
  `ansible.cfg`'s `inventory` takes a comma-separated list, and `enable_plugins` must include
  `ansible.builtin.yaml` for it.
- **"Before Ansible connects":** a guard play with `gather_facts: false` and an `assert` (which
  runs on the control node) refuses without touching the host. An `assert` in a play's
  `pre_tasks` comes after fact gathering, which has already logged in to prod.
- **`any_errors_fatal: true`** on the guard play stops the whole run, dev hosts included: a run
  that mixes prod in without the confirmation does nothing at all.
- **`import_playbook: guard.yml`** first in `site.yml` and `deploy.yml` (and `rolling.yml` imports
  `deploy.yml`): one guard, used everywhere.
- **`confirm_prod | default(false) | bool`**: `-e confirm_prod=true` arrives as the string
  `"true"`; `bool` makes it a boolean, and the default covers runs that don't mention it.
- **Test it with a fixture**, not with prod: an inventory file with a host in `env_prod` at a
  TEST-NET address (`192.0.2.10`, nothing answers) and `ansible_ssh_timeout: 3`. Use names no real
  host has, or cached facts (an-17) get in the way.
- **The dev load balancer:** `groups['role_web'] | intersect(groups['env_dev'])` in
  `role_jump.yml`, in both halves of the `zip`.
- **The prod job with no prod hosts**: `ansible env_prod --list-hosts` prints `hosts (0):`;
  count first and print a notice instead of failing on "no hosts matched".
