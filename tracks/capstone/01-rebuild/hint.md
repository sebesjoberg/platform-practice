# cap-01 hints

Docs:
- The `workflow_run` event (and its `github.event.workflow_run` payload): https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#workflow_run
- Repo variables from the CLI (`gh variable set`): https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables
- `admin_ssh_key` of `azurerm_linux_virtual_machine`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine
- `lifecycle { ignore_changes }`: https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
- `ignore_unreachable` and the `unreachable` test: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html

Traps:
- **`workflows:` takes the workflow's `name:`** (`terraform`), not its file name. And
  `workflow_run` always runs `ansible.yml` *as it is on `main`*: the trigger only works once it's
  merged, and a branch can't test it.
- **`workflow_run` fires for every completed run**: failed ones, and pull request runs too.
  `branches: [main]` filters by the head branch, which a fork can also call `main`; the payload's
  `conclusion`, `event` and `head_repository.full_name` tell them apart. The run gets your
  secrets and your runner, so the guard matters as much as an-16's fork guard.
- **A Terraform run with an `apply-prod` waiting for you hasn't completed.** The Ansible run
  starts once you approve. A Terraform run that skipped its apply (an Ansible-only merge) is
  green and triggers it too: harmless, `site.yml` changes nothing, and a `concurrency` group on
  `apply` keeps the push run and the triggered run from overlapping.
- **`admin_ssh_key` forces a new VM.** Azure can't change a running VM's keys, so adding the
  runner's key replaces *every* web VM at once, `vm-{{PREFIX}}-web-dev-1` included: an outage you
  caused yourself. Read the plan. A key Terraform hands out is a first-boot login; let new VMs get
  the current keys and leave running ones alone.
- **The runner has no key on the first apply.** The jump host (and its runner key) comes from the
  same pipeline that builds the web VMs, and `./lab.sh pause`/`nuke` destroy without CI's
  variables. An empty default that means "no extra key" keeps all of them working.
- **Extra variables beat `set_fact`.** `-e @ci/runner.yml` sets `ansible_user: ops`, and nothing
  a play does can override an extra variable. A template can: extra variables are templated per
  host when they're used, and a template sees the host's facts.
- **An unreachable host leaves the play**, unless the task says `ignore_unreachable: true`. Then
  `register` the result and test it with `is unreachable`. Use `gather_facts: false` in that play:
  gathering would hit the wall first.
- **New VM, new host key.** That's why `ansible.cfg` doesn't record host keys. Old
  ControlPersist connections to the deleted VM die with it.
- **After a pause/resume the jump host is new, and so is the runner's key.**
  `tracks/ansible/lib/runner-register.sh` (which `./lab.sh resume` runs) updates
  `RUNNER_SSH_PUBLIC_KEY`; the VMs resume built still have the old key, which is fine: by then
  `site.yml` has authorized the new one for `ops`.
