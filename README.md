# platform-practice

Hands-on Terraform and Ansible on Azure, auto-graded. You build a small company's platform from
an empty subscription: remote state, a PR → plan → merge → apply pipeline with OIDC, a hub-spoke
network, policy, budgets, versioned modules in their own repo, dev and prod workloads, VMs. Then
you configure those VMs with Ansible the way a platform team runs it: dynamic inventory, tested
roles, Key Vault secrets, rolling updates, drift detection, CI on a self-hosted runner.

Each task takes 15–20 minutes (a few take longer; each says its target). The grader is literal
about names, regions, SKUs and tags, like an exam, and every failing check prints one line that
says why.

## Requirements

- **WSL** with Ubuntu 24.04. Everything runs inside it: Linux `az`, `gh`, `terraform`, `jq`,
  Python 3.12. Not the Windows builds under `/mnt/c` (the lab refuses them), not Git Bash.
- An Azure subscription where you're Owner. Built for a Visual Studio subscription's ~500 kr of
  monthly credit.
- A GitHub account. The lab creates your repos there.
- For the Ansible track: Docker (Molecule), and your clone in your WSL home, not under `/mnt/c`.

Task tf-01 installs and pins the tools, logs you in, and runs `./lab.sh init`.

## Commands

| Command | Does |
|---|---|
| `./lab.sh init` | checks tools and logins, writes `~/.platform-lab/config.env` (prefix, random suffix, repos, your IP) |
| `./lab.sh next [track]` | starts the next task of the track: runs its setup, prints it, starts the clock |
| `./lab.sh task` / `hint` / `solution` `[id]` | the task, docs and traps, the reference approach |
| `./lab.sh grade [id]` | grades the current task; all green marks it done |
| `./lab.sh grade --all` | re-grades every finished task in every track: the regression check |
| `./lab.sh status` | progress and minutes per track |
| `./lab.sh catchup <id>` | puts your repos and Azure in the reference state after task `<id>` |
| `./lab.sh pause` / `resume` | destroys / rebuilds the expensive stacks |
| `./lab.sh cost` | month-to-date spend |
| `./lab.sh nuke` | destroys everything, state storage included; asks before deleting your repos |

Tracks are `terraform`, `ansible` and `capstone`. `./lab.sh next ansible` switches tracks.

## Tracks and order

| Track | Tasks | |
|---|---|---|
| Terraform | tf-01 … tf-31 | foundation, landing zone, modules, environments, day two ([README](tracks/terraform/README.md)) |
| Ansible | an-01 … an-20 | foundation, services, operations ([README](tracks/ansible/README.md)) |
| Capstone | cap-01 | a VM vanishes; both pipelines bring it back with no hands |

1. **tf-01 … tf-25 first.** tf-25 builds the VMs and hands over to the Ansible track.
2. **Then either track, in any order or interleaved.** The day-two Terraform tasks never touch
   what Ansible depends on.
3. **cap-01 last.** It needs both tracks done and ends with `grade --all`.

Within a track, `next` never skips ahead. The escape hatch is `catchup`.

## Cost: always `./lab.sh pause` when you stop

From tf-25 on, VMs, a public IP and private endpoints cost money every hour, used or not.

| State | What runs | Roughly |
|---|---|---|
| Working | 3 small VMs, private endpoints, ACR Basic, Container Apps (scale to zero), capped Log Analytics | 1–2 kr/hour |
| Paused | state storage, landing zone, Log Analytics | 20–30 kr/month |

**The rule: `./lab.sh pause` whenever you stop, `./lab.sh resume` when you're back.** Pause
destroys the workload stacks. Resume re-runs your pipelines on your own `main` (approve
`apply-prod` when it asks) and, from the Ansible track on, puts back the Key Vault objects, the
runner and the configuration. It never touches your code. The budget from tf-12 alerts at 80 %
of 300 kr; `./lab.sh cost` shows where you are.

## Catchup

`./lab.sh catchup <id>` skips ahead, or gets you unstuck:

- It **replaces** the repo's contents with the reference state up to `<id>` (built from the
  tasks' reference files), commits `catchup: <id>` and pushes `main`. Your solutions may differ
  from the reference and still pass, so it never merges.
- **Your work is saved first**, as branch `my-work/<timestamp>` on GitHub and locally. It asks
  before replacing (`--yes` doesn't).
- Then it does what files can't: GitHub settings, pipeline runs (it waits for them), Azure-side
  steps. The replayed tasks count as done.
- `catchup an-XX` replaces only `ansible/` and the Ansible workflow, and replays the Terraform
  reference only if the tf-25 state is missing. It never rolls back later Terraform work.
- `catchup cap-01` replaces everything.

Ansible only? `./lab.sh catchup tf-25`, then `./lab.sh next ansible`.

## Your repos are public

The lab's pipelines need GitHub Actions minutes and features that public repos get for free, so
`<prefix>-platform` and `<prefix>-terraform-modules` are public. That's the point of how they're
built: OIDC instead of cloud secrets, Key Vault for the app's secrets, SSH private keys only on
the machine that made them. Subscription and tenant IDs are identifiers, not secrets. The only
repo secrets are your IP and your budget e-mail address, so the public logs mask them. Never
commit a `.tfvars` file, a key or a token; review what `git add` picks up.

## How it works

Each task is a directory under `tracks/<track>/NN-slug/`: `task.md`, `hint.md`, `solution.md`,
`checks.sh` (the grader), optionally `setup.sh` (an incident), `catchup.sh` and `reference/`.
`./lab.sh selftest --offline [track]` proves every check fails before its task's reference and
passes after it, without Azure; `tests/` holds the bats suite and the linters.
