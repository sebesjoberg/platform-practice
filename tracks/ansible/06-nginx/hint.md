# an-06 hints

Docs:
- `template` with `validate` (the `%s` is a temp file): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html
- Handlers, and when they run: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html
- nginx command line (`-t`, `-c`, `-q`): https://nginx.org/en/docs/switches.html
- `ansible.builtin.uri` (for the Molecule verifier: the container has no curl): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html

Traps:
- **`validate` checks the temp file alone.** `nginx -t -c %s` on a vhost snippet fails: no
  `events`, no `http`. Either own the whole `nginx.conf` (and keep the server block in it, or in a
  file the role writes before it), or write the snippet and run `nginx -t` in a task afterwards,
  restoring the old file when it fails. Validating the main file while the snippet is already in
  `conf.d/` does not protect you: the snippet is live on the next reload whatever the result.
- **Relative includes break under `-c`.** nginx resolves relative paths against the directory of
  the file it checks, a temp directory during validation. Write `include /etc/nginx/mime.types;`,
  not `include mime.types;`.
- **The distribution's default site** (`sites-enabled/default`) also listens on port 80 as
  `default_server`. If your `nginx.conf` still includes `sites-enabled/*`, two default servers
  collide; if it doesn't, remove the file anyway so nobody edits something that has no effect.
- **Handlers run at the end of the play**, once, however many tasks notified them. A handler that
  restarts drops connections; `state: reloaded` doesn't.
- **The hostname** is a fact (`ansible_facts['hostname']`), so the play needs facts (the default).
  On the VMs it equals the VM name.
- **The environment** belongs to the inventory: a `group_vars/env_dev.yml` next to the `env_dev`
  group the inventory builds from the `env` tag. an-19 adds prod by adding `env_prod.yml`.
- **Molecule in a container:** the Ubuntu image ships a `policy-rc.d` that keeps services from
  starting on install, so a role that relies on the package starting nginx works on a VM and
  fails in the container. Start and enable it explicitly.
