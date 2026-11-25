# Getting started

A walk-through for your first session, and the loop you repeat after that. The
[README](README.md) has the full command list, cost table and catchup rules.

## Two kinds of repo

| Repo | What it is | Who edits it |
|---|---|---|
| `platform-practice` (this one) | the lab: tasks, hints, solutions, the grader | nobody: you only run `./lab.sh` from it |
| `<you>/<prefix>-platform` | your platform: Terraform, workflows, later Ansible | you, through commits and (from tf-05) pull requests |
| `<you>/<prefix>-terraform-modules` | your versioned modules, from tf-15 | you |

The grader reads your repos and your Azure subscription and checks them against the task. It
never writes to your repos, except `catchup`, which replaces them on purpose.

## 1. Get the lab into WSL

Everything runs in WSL Ubuntu. Open an Ubuntu terminal (not PowerShell, not Git Bash) and clone
the lab into your Linux home. The Ansible track needs it there, not under `/mnt/c`:

```bash
git clone https://github.com/sebesjoberg/platform-practice.git ~/platform-practice
cd ~/platform-practice
./lab.sh task tf-01
```

Before `init`, the task shows placeholders such as `{{PREFIX}}` instead of your names. That's
expected.

## 2. Do tf-01: tools, logins, init, your repo

tf-01 is the setup, and it is graded like any other task. In short:

1. Install the Linux builds of `terraform` (1.17+), `az`, `gh`, `git` and `jq` in WSL
   (`./lab.sh solution tf-01` has the commands). Check with `type -a az terraform`: the first
   hit must not be under `/mnt/c`.
2. Log in: `az login`, `az account set --subscription <your Visual Studio subscription>`,
   `gh auth login` (HTTPS, let gh be git's credential helper).
3. `./lab.sh init`. It asks for:
   - a **prefix** of 2–6 lowercase letters (default `acme`). It names everything: Azure
     resources (`rg-<prefix>-hub`) and the default repo names. Pick it once.
   - your **GitHub owner**, detected from `gh`.
   - an **owner tag**, your name or alias, put on every Azure resource.
   - the **platform repo** on GitHub, where all your work goes (default `<prefix>-platform`).

   It writes `~/.platform-lab/config.env`, which every later command reads. Then it looks the
   repo up on GitHub: if it's missing it offers to create it (public), and it clones it to
   `~/acme/<repo>`. Say no and you can create it yourself; that's part of tf-01 either way.
4. `./lab.sh next` starts tf-01 properly and shows the task with your own names.
5. In your clone, commit and push a `.gitignore` on `main`; the task says what it must ignore.
6. `./lab.sh grade`. All green marks tf-01 done, and `./lab.sh next` starts tf-02.

## 3. The loop for every task

```bash
cd ~/platform-practice
./lab.sh next        # starts the next task: runs its setup and prints it
#   ...work in ~/acme/<prefix>-platform...
./lab.sh grade       # one line per check; red lines say why
./lab.sh hint        # docs links and the traps, if you're stuck
./lab.sh solution    # the reference approach, if you're really stuck
```

- **tf-01 … tf-04**: you apply Terraform from your machine to bootstrap state storage and the
  CI identity.
- **From tf-05**: your repo has a pipeline. You work on a branch, open a PR (the pipeline posts
  a plan), merge, and the pipeline applies `main`. Grade after the apply has finished.
- Some tasks start with an "incident": `next` breaks something and prints only what a teammate
  would report. Finding the cause is the task.
- `./lab.sh status` shows where you are.

## 4. When you stop: pause

From tf-25 on, VMs and private endpoints cost money every hour, used or not.

```bash
./lab.sh pause       # destroys the expensive stacks; state and landing zone stay
./lab.sh resume      # rebuilds them through your own pipelines when you're back
./lab.sh cost        # month-to-date spend
```

Paused costs about 20–30 kr a month; working costs 1–2 kr an hour. The budget from tf-12
e-mails you at 80 % of 300 kr.

## 5. Order and skipping

1. **tf-01 … tf-25 first.** tf-25 builds the VMs the Ansible track configures.
2. **Then the rest of Terraform (tf-26 … tf-31) and Ansible (an-01 … an-20)**, in any order or
   interleaved. `./lab.sh next ansible` switches tracks.
3. **cap-01 last**: a VM vanishes and both pipelines must bring it back without you.

Stuck for good, or want to skip ahead? `./lab.sh catchup <id>` saves your work as a
`my-work/<timestamp>` branch, then puts your repos and Azure in the reference state after
`<id>`. Ansible only: `./lab.sh catchup tf-25`, then `./lab.sh next ansible`.

## 6. When you're done: nuke

```bash
./lab.sh nuke        # destroys everything in Azure, state storage included
```

It asks before deleting your GitHub repos.
