# platform-practice — design

Date: 2026-11-23
Status: approved 2026-11-23

## Intent

The learner is becoming a platform engineer and wants hands-on, self-paced practice in
Terraform and Ansible on Azure. This is the sibling of `ckad-practice` (same author, same
spirit: prepared tasks, strict auto-grading, hints and solutions, usable without an AI tutor),
but instead of independent exam questions it is **one continuous lab**: the learner builds the
internal platform of a fictional company ("Acme") task by task, stored in their own GitOps
repos, applied through pipelines.

No certification is the goal. The goal is the day-to-day skills of a platform engineer:
bootstrapping state and pipelines, landing-zone networking and identity, reusable versioned
modules, guardrails, environments, and day-two operations (import, refactor, drift, incidents,
upgrades, self-service onboarding).

The learner has **more Ansible experience than Terraform**, so the Ansible track starts at an
intermediate/advanced level.

## Goals

- Two tracks, **Terraform (~32 tasks)** and **Ansible (~21 tasks)**, each task 15–20 minutes,
  so roughly 8–10 hours per track.
- One shared harness (`lab.sh` + grader + task format) for both tracks.
- One shared story: Terraform builds the Azure infrastructure, Ansible configures the VMs it
  creates. The tracks hand over at a defined point (task `tf-25`).
- Each track can also be done on its own: `./lab.sh catchup <task-id>` brings the learner's
  repos and Azure to the reference state of that task. Ansible-only learners run
  `./lab.sh catchup tf-25` first.
- Strict, literal grading like `ckad-practice` (exact names, exact values), but because the
  lab is continuous, a failing check prints a one-line reason, and `./lab.sh grade --all`
  re-grades every completed task to catch regressions.
- Real GitOps: all infra code lives in the learner's GitHub repos; PR → plan (+ comment),
  merge → apply. No long-lived cloud secrets anywhere (OIDC).
- Cost-aware by design: whole lab well under the 500 kr/month Visual Studio credit.

## Non-goals

- Certification prep (Terraform Associate, RHCE).
- AKS. Container Apps covers the container-platform tasks; AKS could be a later add-on track.
- Terragrunt, Atlantis, Spacelift, Terraform Cloud/HCP. Plain Terraform + GitHub Actions.
- Teaching concepts from zero. Task text says *what* to build; hints point to docs.
- An AI tutor mode (ckad-practice has one in its JSON). Can be added later.

## Anti-goals (would make it a failure even if it technically works)

- The credit runs out mid-month and the subscription is disabled.
- A mistake in an early task silently blocks the rest of the lab.
- Graders that pass on a task the learner has not done, or fail on a correct solution that
  differs in irrelevant ways from the reference.
- Secrets (client secrets, SSH private keys, Key Vault values) committed to a repo.
- Requiring Entra ID directory permissions the learner may not have (see Constraints).

## Constraints

- **Azure:** the learner's Visual Studio Professional subscription (~500 kr ≈ $50/month credit,
  spending limit on). The subscription likely lives in the employer's Entra tenant, where
  creating app registrations and groups may be blocked. Therefore: **no `azuread` provider, no
  app registrations, no Entra groups.** CI identity is a **user-assigned managed identity with
  federated credentials**; RBAC targets managed identities. The learner is assumed Owner of
  the subscription (needed for policy and role assignments) — `lab.sh init` verifies this.
- **Region:** `swedencentral` only (enforced by an Azure Policy task).
- **Control node:** the lab runs in **WSL Ubuntu** (present on the learner's machine). Ansible
  cannot run as a Windows control node; using WSL for both tracks keeps one environment.
  Docker Desktop's WSL integration is used for Molecule.
- **Tools** (checked by `lab.sh init`): bash, git, gh, az, jq, terraform (pinned minor),
  tflint, trivy, terraform-docs, python3 + venv (ansible-core pinned, ansible-lint, molecule),
  docker.
- **AI-assistant policy:** Claude does not connect to the learner's Azure subscription unless
  the learner explicitly allows it (see Open questions). Offline validation is always possible.

### Cost model

| State | What runs | Approx. cost |
|---|---|---|
| Working | 3–5 small B-series VMs, 1–2 private endpoints, public IP, ACR Basic, Container Apps (scale to zero), Log Analytics with daily cap | ~1–2 kr/hour |
| Paused (`./lab.sh pause`) | bootstrap + landing-zone only: VNets, private DNS zones, policy, budget, Log Analytics | ~20–30 kr/month |
| Nuked (`./lab.sh nuke`) | nothing — every stack destroyed, then the state storage account and its resource group are deleted too | 0 |

Rules baked into the tasks: cheapest available B-series size in swedencentral (builder verifies
with `az vm list-skus`), Log Analytics daily cap, Key Vault soft-delete retention 7 days with
`purge_soft_delete_on_destroy = true` so pause/resume can recreate vaults with the same name,
no Azure Firewall / Bastion / VPN Gateway / Application Gateway / Standard Load Balancer /
Premium SKUs. A subscription budget with alert is itself a task (`tf-12`).

## Approaches considered

### Repo layout for the learner's code

- **A. One repo throughout.** Simplest; never practises versioned modules consumed by others.
- **B. Two repos from day one** (modules + live). Realistic but heavy before there is anything
  worth versioning.
- **C. One repo first, split modules into their own versioned repo mid-lab. ← chosen.** The
  learner performs the split a growing platform team actually performs; migrating consumers
  to `?ref=vX.Y.Z` and rolling out a breaking module version become tasks.

### How "shared" Terraform + Ansible works

- **1. Shared harness, separate labs** (Ansible against local containers). Simple, but misses
  the Terraform → Ansible handover.
- **2. Shared story only.** Realistic, but Ansible can't start until Terraform has built VMs.
- **3. Shared harness + shared story + catchup so each track runs alone. ← chosen.**

## Decisions made with the learner

- Azure, Visual Studio subscription, ~500 kr/month.
- GitOps on GitHub (learner already uses GitHub, `gh` is authenticated).
- Purpose: becoming a platform engineer; no cert.
- More, smaller tasks (~30 for Terraform).
- Repo layout C; sharing model 3.
- Ansible track pitched above beginner level.

## Design

### Harness repo (`platform-practice`, this repo)

```
platform-practice/
  lab.sh                         # single entry point
  lib/                           # grader, check helpers, templating, catchup engine
  tracks/
    terraform/NN-slug/
      task.md                    # what to build (exact names), target minutes
      hint.md                    # docs to read + traps
      solution.md                # reference approach + how to verify
      checks.sh                  # graded checks (see below)
      setup.sh                   # optional: prepares/injects state (incidents, imports)
      catchup.sh                 # optional: non-file steps to reach reference state
      reference/                 # files this task adds/changes in the learner's repo(s)
    ansible/NN-slug/ ...same...
  README.md
```

Commands (mirroring ckad-practice):

| Command | Does |
|---|---|
| `./lab.sh init` | checks tools, az login, Owner on sub, gh auth; writes `~/.platform-lab/config.env` (subscription, GitHub owner, repo names, name prefix, random suffix for globally-unique names, learner public IP) |
| `./lab.sh next [track]` | next unfinished task in order: runs its `setup.sh`, shows `task.md`, starts the clock |
| `./lab.sh task [id]` / `hint [id]` / `solution [id]` | as in ckad-practice |
| `./lab.sh grade [id]` | grades current task; time vs target; marks done on all-pass |
| `./lab.sh grade --all` | re-grades every completed task (regression check) |
| `./lab.sh status` | progress table per track |
| `./lab.sh catchup <id>` | brings repos + Azure to the reference state after task `<id>` |
| `./lab.sh pause` / `resume` | destroy / recreate the expensive stacks (see Cost model) |
| `./lab.sh nuke` | destroy every stack, then delete the state storage account/RG, the CI identity, and (asked separately) the learner's GitHub repos |
| `./lab.sh cost` | month-to-date spend from the Consumption API |

Progress lives in `~/.platform-lab/progress` (task id, started, finished).

**Order:** tasks are sequential within a track. `next` refuses to skip ahead; the escape hatch is
`catchup`. Ansible tasks require the `tf-25` reference state (real or via catchup); `next ansible`
checks for it and tells the learner what to run.

**Checks format.** `checks.sh` is sourced by the grader and calls a helper:

```bash
check "Hub VNet exists with 10.0.0.0/16" \
  "az network vnet show -g rg-${PREFIX}-hub -n vnet-${PREFIX}-hub --query 'addressSpace.addressPrefixes[0]' -o tsv | grep -qx 10.0.0.0/16" \
  "expected vnet-${PREFIX}-hub in rg-${PREFIX}-hub with address space 10.0.0.0/16"
```

Each check runs in `bash -o pipefail` with stdin from `/dev/null` and a timeout (same lessons as
ckad-practice). Check kinds used across tasks: Azure state (`az ... --query`), GitHub state
(`gh api`: workflows, runs, rulesets, PR comments, absence of secrets), code properties
(files, `terraform show -json`, grep), behaviour (`terraform plan -detailed-exitcode` = no
drift, resource IDs unchanged vs a snapshot taken by `setup.sh`, Ansible second run
`changed=0`, curl through the load balancer during a rolling update).

**Exact names.** Tasks dictate exact resource names built from `PREFIX` (default `acme`) and,
for globally unique names, `SUFFIX`. Graders are literal about names, locations, SKUs, tags;
they are lenient about *how* (module structure, file layout) unless that is the point of the
task.

**Catchup.** For task N: apply `reference/` overlays of tasks 1..N in order into the learner's
repo(s) (templated with config values; a `reference/.delete` list removes files), run each
task's `catchup.sh` (GitHub settings, bootstrap applies, Azure-side steps), commit on a
`catchup/<id>` branch, and apply. Catchup is also what `resume` uses.

**Catchup vs. the learner's own code** *(builder's call)*. Graders accept solutions that differ
from the reference, so overlaying reference deltas on a divergent repo cannot work. Therefore:
- `catchup <id>` **replaces** the repo contents with the reference state up to `<id>` (built by
  replaying overlays 1..N from an empty tree, so effectively a snapshot). The learner's current
  `main` is first saved as branch `my-work/<timestamp>`; catchup asks for confirmation.
- Catchup runs locally from WSL for steps before pipelines exist (tf-01..tf-05), then pushes to
  `main` and lets the pipelines apply.
- `resume` never touches code: it re-runs the pipelines on the learner's own `main` (Terraform
  stacks, then the Ansible pipeline if the learner is past an-16, otherwise the local playbooks),
  so recreated VMs come back configured.

**Track order** *(builder's call)*. tf-01..tf-25 first. After that the tracks may be done in any
order or interleaved. Terraform tasks after tf-25 must not break Ansible's dependencies, except the
joint capstone. `tf-32` and `an-21` are merged into one cross-track capstone that requires both
tracks to be otherwise complete. `grade --all` covers both tracks. `catchup an-XX` replays only
the Ansible overlays, and replays the Terraform reference only if the tf-25 baseline checks fail.
It never rolls back later Terraform work.

**Key Vault network access** *(builder's call)*. Public network access stays enabled (RBAC-only
data plane), with a private endpoint added on top to teach private DNS. GitHub-hosted runners and
WSL can reach the vault before any in-VNet runner exists.

**Self-test.** `./lab.sh selftest [track]`: for each task, grade *before* its catchup (must
fail at least one check) and *after* (must pass all). This is how graders are validated
against a real subscription.

### Learner's repos (created during the lab)

- `acme-platform` — `terraform/` stacks + `ansible/` + `.github/workflows/`.
- `acme-terraform-modules` — created in `tf-19`, git-tagged releases.

Terraform stacks (separate state each): `bootstrap`, `landing-zone`, `shared` (ACR, runner),
`env-dev`, `env-prod`, later `observability`, `teams/*`. Pause destroys everything except
`bootstrap` and `landing-zone`.

### Terraform track (draft curriculum)

**Phase 0 — Foundation**
1. `tf-01` Setting up: install and pin the tools in WSL, `az login` + select the subscription, create the **public** `acme-platform` repo with a sane `.gitignore`. Part of the lab, not a prerequisite.
2. `tf-02` `bootstrap` stack: state RG + storage account (versioning, soft delete, TLS 1.2, no public blob access) with local state.
3. `tf-03` Migrate bootstrap's own state into the account it created (Entra auth, no shared keys).
4. `tf-04` CI identity: user-assigned managed identity, federated credentials (main + pull_request), least-privilege RBAC (Contributor + constrained RBAC Administrator + Storage Blob Data Contributor on state).
5. `tf-05` GitHub Actions: PR → fmt/validate/plan + plan comment; merge → apply. IDs as repo variables, no secrets.
6. `tf-06` Branch protection / ruleset with required plan check; `prod` environment with required reviewer.

**Phase 1 — Landing zone**
7. `tf-07` Naming + tagging conventions (locals), validated variables.
8. `tf-08` Hub VNet, subnets, NSGs.
9. `tf-09` Spokes (dev, prod) with `for_each`, bidirectional peering.
10. `tf-10` Private DNS zones linked to all VNets.
11. `tf-11` Azure Policy: custom "require `owner` tag" + built-in allowed locations.
12. `tf-12` Subscription budget + action group alert.
13. `tf-13` Log Analytics (daily cap) + Activity Log diagnostic setting.
14. `tf-14` Split into stacks; env stacks read hub via data sources.

**Phase 2 — Modules**
15. `tf-15` Extract `spoke` module; `moved` blocks; zero destroys (IDs snapshot-checked).
16. `tf-16` Module quality: validation, descriptions, outputs, terraform-docs, version constraints.
17. `tf-17` `terraform test` for the module, in CI.
18. `tf-18` tflint + trivy in CI, fix findings.
19. `tf-19` Split modules into `acme-terraform-modules`, tag `v1.0.0`, consume via `?ref=`.
20. `tf-20` Breaking change `v2.0.0`: dev on v2, prod still on v1 (canary).

**Phase 3 — Environments & workloads**
21. `tf-21` `app-env` module: RG, managed identity, Key Vault (RBAC) with private endpoint, role assignment.
22. `tf-22` ACR (Basic) in `shared`; AcrPull for workload identities.
23. `tf-23` Container Apps environment + app in dev (ACR via identity, Key Vault secret reference).
24. `tf-24` Prod from the same module; pipeline matrix; prod apply gated by environment approval.
25. `tf-25` **Handover:** `linux-vm` module; jump/runner VM in hub (public IP, NSG locked to learner IP, system-assigned identity with Reader + Key Vault Secrets User), 2 web VMs in dev spoke (no public IP), tags `role`/`env` for dynamic inventory.

**Phase 4 — Day two**
26. `tf-26` Import a "click-ops" storage account (created by `setup.sh`) with an `import` block; clean plan.
27. `tf-27` Drift incident (setup changes an NSG rule + removes a tag); scheduled drift-detection workflow that opens an issue; reconcile.
28. `tf-28` State lock incident (setup holds a blob lease on env-dev state); diagnose + `force-unlock`.
29. `tf-29` Move Log Analytics to an `observability` stack with `removed` + `import`, no destroy.
30. `tf-30` Provider lockfile for multiple platforms; Dependabot/Renovate for providers and module refs; upgrade via PR.
31. `tf-31` Self-service: onboard team "payments" with one module call (RG, identity + federated credential for their repo, budget, RBAC).
32. `tf-32` Capstone: destroy and rebuild env-dev through the pipeline; `grade --all` green.

### Ansible track (draft curriculum)

Runs in WSL against the `tf-25` VMs via the jump host.

**Phase A — Foundation**
1. `an-01` `ansible/` layout, `ansible.cfg`, pinned ansible-core in a venv, pinned collections.
2. `an-02` Dynamic inventory (`azure.azcollection.azure_rm`), keyed groups by tag, ProxyJump via jump VM.
3. `an-03` `base` role: users, sshd hardening, unattended upgrades, chrony; idempotent.
4. `an-04` ansible-lint (production profile) + yamllint + pre-commit.
5. `an-05` Molecule (docker driver) for `base` with a verifier.

**Phase B — Services**
6. `an-06` `nginx` role: templates, handlers, `validate:` before reload.
7. `an-07` Secrets from Key Vault (azure collection lookup), nothing secret in the repo.
8. `an-08` TLS on 443 from a Key Vault certificate.
9. `an-09` App as a systemd service with health endpoint; `uri` wait.
10. `an-10` HAProxy role on the jump VM load-balancing the web VMs.

**Phase C — Operations**
11. `an-11` Rolling update: `serial`, `max_fail_percentage`, drain/enable in HAProxy via `delegate_to`; grader curls continuously during the run and requires zero failures.
12. `an-12` Config drift incident (setup edits config + stops a service by hand); `--check --diff` scheduled job; remediate.
13. `an-13` Custom module with check-mode support.
14. `an-14` Package roles as collection `acme.platform`, install from git by tag.
15. `an-15` `gh_runner` role: register the jump VM as a self-hosted GitHub runner.
16. `an-16` Ansible CI on the self-hosted runner (managed identity, no secrets): PR → lint + molecule + check/diff on dev; merge → apply dev; prod gated.
17. `an-17` Speed: fact caching, pipelining, forks, `strategy` choices.
18. `an-18` `block`/`rescue`/`always` deploy with automatic rollback (grader deploys a broken version, old version must keep serving).
19. `an-19` Prod inventory + group_vars per env + `assert` guard against accidental prod runs.
20. `an-20` Compliance report playbook publishing an artifact in CI.
21. `an-21` Capstone (cross-track): grader deletes a web VM; Terraform pipeline recreates it and triggers the Ansible pipeline, which brings it back into the HAProxy pool automatically.

## Left to the builder

- Exact wording of tasks, hints and solutions; exact check commands; target minutes per task.
- Reordering or merging tasks inside a phase if dependencies demand it; the phase outline and
  the handover point stay.
- VM size, OS image (Ubuntu LTS), exact CIDRs and names (documented in `task.md`).
- Implementation details of templating, overlays and catchup.
- Pinned tool and provider versions (latest stable at build time).

## Decided after review

- **Public repos** for `acme-platform` and `acme-terraform-modules`. Rulesets and `prod`
  environment reviewers work on GitHub Free; modules are consumable without CI auth. The
  self-hosted runner (an-15/an-16) is hardened: fork PRs need approval, runner jobs only run
  for same-repo PRs, pushes to `main` and `workflow_dispatch`. Hardening is part of the task.
- **Setup is task tf-01**, not a prerequisite.
- **`nuke` removes the Azure state too** (state storage account and its resource group, after all
  stacks are destroyed).
- **Testing:** build and validate offline now (terraform fmt/validate/test, tflint, trivy,
  shellcheck, ansible-lint, Molecule in local Docker, grader dry runs against fixtures). The
  learner will later grant access to the Visual Studio subscription for `./lab.sh selftest`;
  until then Claude does not connect to it.
