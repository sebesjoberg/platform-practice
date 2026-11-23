# an-17 hints

Docs:
- Speeding up playbooks (forks, pipelining, fact caching): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html
- Fact caching and `gathering`: https://docs.ansible.com/ansible/latest/plugins/cache.html
- The `ssh` connection's pipelining and `ssh_args`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ssh_connection.html
- Strategies (`linear`, `free`): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/free_strategy.html
- `ansible.posix.profile_tasks`: https://docs.ansible.com/ansible/latest/collections/ansible/posix/profile_tasks_callback.html

Traps:
- **`ssh_args` replaces the defaults** (an-02): a new `ControlPersist` goes into the same line,
  next to `IdentitiesOnly=yes` and the host-key options, or you lose them.
- **Pipelining and `become`** need `sudo` without `requiretty`; Ubuntu's sudoers doesn't set it.
  It also removes the temp-file dance when becoming an unprivileged user (an-15's `gh-runner`).
- **`gathering = smart` + a cache** skips fact gathering for hosts with fresh cached facts. After
  `./lab.sh pause`/`resume` the VMs are new but have the same names: keep the timeout short (an
  hour or two), or `rm -rf` the cache directory after a resume.
- **`cacheable: true`** writes a `set_fact` into the cache files, in plain text. Role `nginx`
  reads the TLS key into a fact (an-08) without it: keep it that way.
- **The cache directory is per machine.** Gitignore it; CI's checkout starts without one (and
  `actions/checkout` cleans ignored files), which is fine.
- **`strategy: free`** lets each host run ahead, so tasks of different hosts interleave and
  `run_once` or a task that relies on another host having finished is no longer safe. In
  `site.yml` the baseline play reads the runner's key with `run_once` and `delegate_to`, and the
  load balancer play must come after the web servers' play; strategies apply per play, so
  ordering between plays is kept either way.
- **Measure the same thing twice**: the second run of an unchanged fleet, from the same shell
  (the SSH control sockets of the first run are part of what you measure).
