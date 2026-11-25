---
id: an-19
title: Prod in the inventory, and a guard
target_minutes: 20
requires: [tf-25, an-18]
---
# an-19 Prod in the inventory, and a guard

Prod web servers are on the roadmap (their vault `kv-{{PREFIX}}-prod-{{SUFFIX}}` exists since
tf-24), and the day they appear in the inventory, every habit of the last weeks becomes
dangerous: a plain `ansible-playbook site.yml` would configure prod, `deploy.yml -e
app_version=broken` would experiment on it, and HAProxy on the hub would happily put prod servers
behind the dev load balancer. Make prod a first-class environment now, while it is empty, with
guard rails that need a deliberate word to pass.

## Deliverables

- [ ] The inventory knows prod: `rg-{{PREFIX}}-prod` in the Azure inventory's resource groups, and
      a group **`env_prod`** that exists even while it has no hosts (a static inventory file next
      to `azure_rm.yml`, loaded through `ansible.cfg`). Explain your choice in a comment.
- [ ] `group_vars/env_prod.yml`: `acme_env: prod`, the prod vault's URL, `acme_log_level: info`.
- [ ] A **guard**: any run whose hosts include `env_prod` fails on an `assert` **before Ansible
      connects to a prod host**, unless it says `-e confirm_prod=true`. It covers `site.yml` and
      `deploy.yml` (and with them `rolling.yml`).
- [ ] HAProxy's backends are `role_web` **∩** `env_dev`: a prod web server never joins the dev
      load balancer.
- [ ] `ansible.yml`: the dev jobs (`check`, `apply`, `drift`) limit their runs to
      `env_dev:env_hub`; a new job **`apply-prod`** (dispatch `env=prod`, on the runner, the fork
      guard) uses the GitHub environment **`prod`** (its required reviewer approves, tf-06), runs
      `site.yml --limit env_prod -e confirm_prod=true`, and says so when `env_prod` has no hosts
      yet. No other job ever says `confirm_prod`.
- [ ] Lint-clean; a second `site.yml` run reports `changed=0`.

## Done when

`ansible-inventory --graph` shows an empty `@env_prod`; against an inventory file of your own with
a fake host in `env_prod` (an address nothing answers on), `ansible-playbook site.yml -i <file>
--limit env_prod` fails at your assert without a connection attempt, and with
`-e confirm_prod=true` gets past it (then fails to reach the fake host); `./lab.sh grade` passes
(it runs exactly that against its own fixture).
