# platform-practice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-paced, auto-graded, continuous Terraform + Ansible lab on Azure (`./lab.sh`), in which the learner builds the "Acme" internal platform in their own public GitOps repos.

**Architecture:** A bash harness (`lab.sh` + `lib/*.sh`) drives task directories under `tracks/<track>/NN-slug/`. Each directory holds the task text, hint, solution, graded checks, optional setup/catchup scripts, and a `reference/` overlay of the files that task adds to the learner's repo. Catchup replays the overlays. Offline validation replays them into a temp dir and runs terraform/ansible linters plus the code-only checks. Live validation (`selftest`) runs everything against Azure later, once the learner allows it.

**Tech Stack:** bash 5, bats-core, shellcheck, jq, az CLI (Linux build inside WSL), gh, Terraform (latest stable, azurerm 4.x), tflint + azurerm ruleset, trivy, terraform-docs, ansible-core (pinned in a venv), azure.azcollection, ansible-lint, yamllint, Molecule (docker driver), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-23-platform-lab-design.md`

## Global Constraints

- **Runtime:** everything runs in WSL Ubuntu 24.04 from the repo root. Verify commands below are WSL commands. All repo files use LF (`.gitattributes`: `* text=auto eol=lf`).
- **No Azure or learner-GitHub calls during the build.** Claude does not connect to the Visual Studio subscription until the learner explicitly allows it (Task 16). Offline tests use fake `az`/`gh`/`terraform` from `tests/fakes/` on `PATH`.
- **Region:** `swedencentral`. **No** `azuread` provider, app registrations or Entra groups. CI auth uses a user-assigned managed identity with federated credentials.
- **Banned SKUs/services:** Azure Firewall, Bastion, VPN Gateway, Application Gateway, Standard Load Balancer, any Premium SKU, AKS. VMs use the cheapest B-series size available in swedencentral (look it up in the docs; record it in `tracks/terraform/README.md`). Log Analytics has a daily cap of 0.1 GB. Key Vault uses `soft_delete_retention_days = 7`, no purge protection, and provider `features { key_vault { purge_soft_delete_on_destroy = true } }`.
- **Config contract** (`~/.platform-lab/config.env`, written by `lab.sh init`, sourced by every command and exported to checks): `PREFIX` (default `acme`, `^[a-z]{2,6}$`), `SUFFIX` (6 chars `[a-z0-9]`, random at init), `LOCATION=swedencentral`, `SUBSCRIPTION_ID`, `TENANT_ID`, `GH_OWNER`, `LIVE_REPO` (default `${PREFIX}-platform`), `MODULES_REPO` (default `${PREFIX}-terraform-modules`), `LIVE_DIR` (learner's clone, default `~/acme/${LIVE_REPO}`), `MODULES_DIR` (default `~/acme/${MODULES_REPO}`), `LEARNER_IP`, `OWNER_TAG` (learner's name/alias, used for the `owner` tag). Lab state lives in `~/.platform-lab/` (`LAB_HOME`, overridable for tests).
- **Templating:** reference files use the tokens `{{PREFIX}} {{SUFFIX}} {{LOCATION}} {{SUBSCRIPTION_ID}} {{TENANT_ID}} {{GH_OWNER}} {{LIVE_REPO}} {{MODULES_REPO}} {{LEARNER_IP}} {{OWNER_TAG}}` and nothing else.
- **Naming and addressing table (binding for every content task, task.md shows the expanded names):**

| Thing | Name / value |
|---|---|
| State RG / account / container | `rg-{P}-tfstate` / `st{P}tfstate{S}` / `tfstate` |
| State keys | `bootstrap.tfstate`, `landing-zone.tfstate`, `shared.tfstate`, `env-dev.tfstate`, `env-prod.tfstate`, `observability.tfstate`, `teams-payments.tfstate` |
| CI identity | `id-{P}-github-ci` in `rg-{P}-tfstate`; federated credentials `gh-main`, `gh-pr`, `gh-env-prod` |
| Hub | `rg-{P}-hub`, `vnet-{P}-hub` 10.0.0.0/16: `snet-shared` 10.0.1.0/24, `snet-runner` 10.0.2.0/24, `snet-pe` 10.0.3.0/24 |
| Spokes | `rg-{P}-dev` / `rg-{P}-prod`, `vnet-{P}-dev` 10.1.0.0/16 / `vnet-{P}-prod` 10.2.0.0/16: `snet-app` x.1.0/24, `snet-pe` x.2.0/24, `snet-aca` x.4.0/23 (delegated `Microsoft.App/environments`) |
| Peering | `peer-hub-to-{env}`, `peer-{env}-to-hub` |
| NSGs | `nsg-{P}-{vnet-short}-{subnet}` e.g. `nsg-acme-hub-runner` |
| Private DNS | `privatelink.vaultcore.azure.net`, `privatelink.blob.core.windows.net` in `rg-{P}-hub`, links `link-{vnet name}` |
| Policy | definition + assignment `{P}-require-owner-tag`; assignment `{P}-allowed-locations` (built-in) |
| Budget | `budget-{P}-monthly`, amount 300, alert at 80 % actual and 100 % forecast, action group `ag-{P}-budget` |
| Log Analytics | `law-{P}-platform` in `rg-{P}-hub` |
| Shared | `rg-{P}-shared`, ACR `acr{P}{S}` (Basic) |
| Workloads | `id-{P}-app-{env}`, `kv-{P}-{env}-{S}`, `cae-{P}-{env}`, `ca-{P}-hello-{env}`, private endpoint `pe-kv-{P}-{env}` |
| VMs | `vm-{P}-jump` in `rg-{P}-shared` / `snet-runner` with `pip-{P}-jump`; `vm-{P}-web-dev-1`, `vm-{P}-web-dev-2` in `rg-{P}-dev` / `snet-app` (no public IP). Tags `role` = `jump`/`web`, `env` = `hub`/`dev` |
| Day-two | click-ops `rg-{P}-legacy` / `st{P}legacy{S}`; team `rg-{P}-payments`, `id-{P}-payments-ci`, `budget-{P}-payments` |
| Required tags on every RG | `owner` = `{OWNER_TAG}`, `env`, `managed_by` = `terraform` |

- **Task directory contract:** `tracks/<track>/NN-slug/` with `task.md` (front matter `id`, `title`, `target_minutes`, `requires`), `hint.md`, `solution.md`, `checks.sh`, and optionally `setup.sh`, `catchup.sh`, `reference/` (paths relative to the target repo: `live/…` → `LIVE_DIR`, `modules/…` → `MODULES_DIR`; `reference/.delete` lists paths to remove). Track ids: `tf-01…tf-31`, `an-01…an-20`, `cap-01` (joint capstone, merges tf-32 + an-21 from the spec).
- **Check API (sourced by `checks.sh`):** `check "<name>" '<cmd>' "<reason if failed>"` (needs cloud/GitHub) and `check_code "<name>" '<cmd>' "<reason>"` (offline-safe, reads only `LIVE_DIR`/`MODULES_DIR`). Each command runs `bash -o pipefail -c` with cwd `LIVE_DIR`, stdin `/dev/null`, 60 s timeout, config exported. Every task has at least one `check_code` unless the task is purely Azure/GitHub state; the reason says so in a comment.
- **Strictness:** literal on names, locations, SKUs, tags, CIDRs; lenient on file layout and module structure unless the task is about that.

**User decisions (already made):**
- Azure on the learner's Visual Studio Professional subscription, ~500 kr/month credit.
- Purpose: becoming a platform engineer, no cert.
- About 30 small Terraform tasks; Ansible track pitched above beginner level.
- Repo layout C: one repo, modules split into a versioned repo mid-lab.
- Sharing model 3: shared harness, shared story, catchup so each track runs alone.
- Public GitHub repos for the learner's code.
- Setup is task tf-01, part of the lab.
- `nuke` also deletes the Azure state (account + RG).
- Test offline now. The learner grants subscription access later for selftest.

## Review Focus

1. **Linux tools vs. Windows tools in WSL** (`az` resolves to `/mnt/c/…/az` on this machine): `lab.sh init` and every command must refuse Windows binaries (`/mnt/c/*` paths) and plain Git Bash/MSYS, with a message saying how to install the Linux build. Test in Task 2.
2. **Expired or wrong `az` login before grading:** without a preflight, every cloud check fails with misleading reasons. `grade` must preflight `az account show` against `SUBSCRIPTION_ID` and `gh auth status`, then abort with one clear line. Test in Task 3.
3. **Catchup with uncommitted changes or not on `main`:** it must refuse while there are uncommitted changes, and must always back up `main` to `my-work/<timestamp>` before replacing. Test in Task 4.
4. **Learner IP changed (home vs. office):** the NSG lockout breaks SSH/jump. `lab.sh init --refresh-ip` updates `LEARNER_IP` and prints the stacks to re-apply. Test in Task 2.
5. **Grading while paused:** `grade` warns and exits non-zero without running checks when `LAB_HOME/paused` exists, instead of showing a wall of FAILs. Test in Task 5.

---

### Task 1: Dev tooling and repo skeleton

**Goal:** Install the offline toolchain in WSL user space (no sudo) and lay down the repo skeleton so `bats` and `shellcheck` run.

**Files:**
- Create: `scripts/install-dev-tools.sh`, `.gitattributes`, `.gitignore`, `.editorconfig`, `tests/test_helper.bash`, `tests/skeleton.bats`, `tests/fakes/az`, `tests/fakes/gh`, `tests/fakes/terraform`, `README.md` (stub)

**Acceptance Criteria:**
- [ ] `scripts/install-dev-tools.sh` installs pinned terraform, tflint, trivy, terraform-docs, shellcheck and bats-core into `~/.local/bin`, plus ansible-core, ansible-lint, yamllint, molecule and molecule-plugins[docker] into `~/.local/share/platform-practice/venv`. Re-running it is a no-op.
- [ ] Fakes append their argv to `$FAKE_LOG` and answer from `$FAKE_DIR/<tool>/<joined-args>` files (exit code in `.rc`, stdout in `.out`). A missing response file → exit 1 with `fake: no response for …` on stderr.
- [ ] `tests/test_helper.bash` sets `LAB_HOME` to a temp dir, puts `tests/fakes` first on `PATH`, and writes a fixture `config.env` (PREFIX=acme, SUFFIX=abc123, GH_OWNER=learner, LIVE_DIR and MODULES_DIR in temp dirs).

**Verify:** `bats tests/skeleton.bats && shellcheck scripts/*.sh tests/fakes/*` → all ok, no findings

**Steps:**
- [ ] Write `tests/skeleton.bats` with `fake az returns canned output` (create `$FAKE_DIR/az/account show.out`, assert `az account show` prints it and `$FAKE_LOG` contains `az account show`) and `fake without response fails` (assert status 1 and the stderr message).
- [ ] Run it → FAIL (no fakes yet).
- [ ] Write the fakes, helper and installer (versions as variables at the top of the installer, latest stable at build time, checksums verified).
- [ ] Run the installer, then `bats tests/skeleton.bats` → PASS.
- [ ] Commit `chore: dev tooling, fakes and repo skeleton`.

### Task 2: lab.sh core — environment guard, init, task lookup, task/hint/solution/next/status

**Goal:** The entry point with config, progress state and the read-only task commands working against fixture tracks.

**Files:**
- Create: `lab.sh`, `lib/common.sh`, `lib/config.sh`, `lib/tasks.sh`, `lib/progress.sh`, `tests/fixtures/tracks/demo/01-first/{task.md,hint.md,solution.md,checks.sh}`, `tests/fixtures/tracks/demo/02-second/…`, `tests/core.bats`

**Acceptance Criteria:**
- [ ] `lib/common.sh`: `require_linux_env` exits 3 with `run the lab inside WSL/Linux` when `uname -s` isn't Linux or `$MSYSTEM` is set. `need <tool…>` exits 3 naming any tool missing or resolving under `/mnt/` (`<tool> is the Windows build; install the Linux one: <hint>`).
- [ ] `lab.sh init` asks for or accepts flags `--prefix --gh-owner --owner-tag --live-dir`, reads the subscription/tenant from `az account show`, checks the Owner role with `az role assignment list --assignee <me> --scope /subscriptions/<id> --query "[?roleDefinitionName=='Owner']"`, gets the learner IP from `https://api.ipify.org`, and writes `config.env`. `init --refresh-ip` rewrites only `LEARNER_IP` and prints `re-apply: shared (tf-25 NSG)`.
- [ ] `lib/tasks.sh`: `task_ids [track]` lists ids in directory order. `task_dir <id>` and `task_meta <id> <key>` read front matter. `TRACKS_DIR` is overridable (tests point it at the fixtures).
- [ ] `lib/progress.sh`: TSV `$LAB_HOME/progress` (`id<TAB>started<TAB>finished`). Functions `progress_start`, `progress_finish`, `progress_done <id>`, `current_task`.
- [ ] `lab.sh next [track]` picks the first unfinished task whose `requires` are all done, runs its `setup.sh` if present, prints `task.md` without front matter plus `target: N min`, and records the start. It refuses with `finish <id> first or ./lab.sh catchup <id>` when the next task is blocked.
- [ ] `task|hint|solution [id]` print the file (default: current task). `status` prints a per-track table (`id title done/—  minutes taken`).

**Verify:** `bats tests/core.bats` → all tests pass

**Steps:**
- [ ] Write `tests/core.bats` tests: `rejects MSYS`, `rejects windows az under /mnt`, `init writes config from fake az`, `refresh-ip only changes LEARNER_IP`, `task_ids orders by directory`, `next starts first task and prints target`, `next refuses blocked task`, `status shows done tasks`.
- [ ] Run → FAIL.
- [ ] Implement. `lab.sh` is a thin dispatcher: `case "$1" in init|next|task|hint|solution|status|grade|catchup|pause|resume|nuke|cost|selftest)`, each sourcing its `lib/` file.
- [ ] Run → PASS. Run `shellcheck lab.sh lib/*.sh` → clean.
- [ ] Commit `feat: lab.sh core, config, task lookup and progress`.

### Task 3: Grader

**Goal:** `./lab.sh grade [id]` and `grade --all` with the check API, preflight and timing.

**Files:**
- Create: `lib/grade.sh`, `lib/checks-api.sh`, `tests/grade.bats`, fixture `checks.sh` files with passing, failing, hanging and stdin-reading checks

**Acceptance Criteria:**
- [ ] `checks-api.sh` defines `check` and `check_code`. Output per check is `✓ PASS  <name>` or `✗ FAIL  <name>` + an indented `→ <reason>`. Colour only when stdout is a TTY and `NO_COLOR` is unset.
- [ ] Commands run per the Global Constraints check API (pipefail, cwd `LIVE_DIR`, stdin `/dev/null`, 60 s timeout → FAIL with `→ timed out`).
- [ ] Preflight before any `check` (skipped when a task has only `check_code`): `az account show --query id -o tsv` must equal `SUBSCRIPTION_ID`, else exit 4 with `az not logged in to the lab subscription (az login; az account set -s …)`. `gh auth status` must succeed, else exit 4.
- [ ] Summary line `N/M passed — took X min (target Y)`. On all-pass it marks the task finished. Exit 0 all-pass, 1 any fail, 2 unknown id.
- [ ] `grade --all` grades every finished task in order and prints `regressions: <ids>` or `no regressions`.
- [ ] `grade --offline <id>` runs only `check_code` checks (used by selftest offline).

**Verify:** `bats tests/grade.bats` → all tests pass

**Steps:**
- [ ] Tests: `pass and fail are reported with reason`, `pipefail fails a check whose first command fails`, `hanging check times out`, `stdin-reading check does not eat the loop`, `preflight aborts on wrong subscription`, `code-only task skips preflight`, `all-pass marks finished and prints timing`, `grade --all reports regression`, `offline runs only check_code`. Use `GRADE_TIMEOUT=2` in the timeout test.
- [ ] Run → FAIL. Implement. Run → PASS. Run shellcheck.
- [ ] Commit `feat: grader with check API, preflight and regression mode`.

### Task 4: Templating and catchup engine

**Goal:** `./lab.sh catchup <id>` rebuilds the learner's repo(s) to the reference state of `<id>` safely.

**Files:**
- Create: `lib/template.sh`, `lib/catchup.sh`, `tests/catchup.bats`, fixture tracks with `reference/live/…`, `reference/modules/…`, `reference/.delete`, `catchup.sh`

**Acceptance Criteria:**
- [ ] `render_tree <src> <dst>` copies the files and replaces exactly the tokens in Global Constraints. A file containing any other `{{…}}` token makes it exit 5 naming the file and token. Binary files are copied untouched.
- [ ] `build_reference <id> <out>` replays tasks in track order up to `<id>` (for `an-*`/`cap-01`: the Terraform reference up to `tf-25` first, then the Ansible overlays) from an empty tree, applying `.delete` lists. Output dirs are `<out>/live`, `<out>/modules`.
- [ ] `catchup <id>`: refuses (exit 6) if `LIVE_DIR` has uncommitted changes. Pushes the current `main` to `my-work/<YYYYmmdd-HHMMSS>`, then makes `main` match the reference (keeping `.git`), commits `catchup: <id>`, and asks `y/N` before `git push --force-with-lease`. Same for `MODULES_DIR` once the reference has `modules/`. Then runs each replayed task's `catchup.sh` in order, with `CATCHUP_PHASE=after-push`.
- [ ] `catchup an-XX` / `cap-01` replaces only `ansible/` and `.github/workflows/ansible*.yml` (Terraform files and later Terraform work stay as they are). It replays the Terraform reference (full catchup to `tf-25`) only when the `tf-25` checks fail (`grade` in quiet mode).
- [ ] `--yes` skips the prompts (used by selftest).

**Verify:** `bats tests/catchup.bats` → all tests pass

**Steps:**
- [ ] Tests (using local bare repos as remotes): `render replaces known tokens`, `render rejects unknown token`, `replay applies overlays and deletes`, `catchup refuses dirty tree`, `catchup backs up main to my-work branch`, `catchup result equals reference tree`, `catchup runs task catchup.sh in order`, `ansible catchup skips terraform when tf-25 passes`.
- [ ] Run → FAIL. Implement. Run → PASS. Run shellcheck.
- [ ] Commit `feat: templating and catchup engine`.

### Task 5: pause, resume, nuke, cost

**Goal:** Cost-control commands that operate on the learner's stacks, tested against fakes.

**Files:**
- Create: `lib/ops.sh`, `tests/ops.bats`

**Acceptance Criteria:**
- [ ] `pause`: destroys in this order (state keys from the naming table): `teams-payments`, `observability`, `env-prod`, `env-dev`, `shared`. Each runs `terraform -chdir=$LIVE_DIR/terraform/<stack> init -input=false` and `destroy -auto-approve`, skipping stacks whose directory doesn't exist. Then writes `$LAB_HOME/paused`.
- [ ] `resume`: removes `paused` and runs `gh workflow run terraform.yml --ref main -f stacks=all` when the workflow exists (after tf-05), else applies locally in reverse order. Past `an-16` it also runs `gh workflow run ansible.yml --ref main -f env=dev`. Before that it runs the local playbook `ansible-playbook -i inventory site.yml`.
- [ ] `grade` while paused prints `lab is paused — ./lab.sh resume first` and exits 7 (Review Focus 5).
- [ ] `nuke`: double confirmation (type the prefix). Destroys every stack including `landing-zone`, then `bootstrap` (migrated back to local state first: `init -migrate-state -backend=false`). Then deletes `rg-{P}-tfstate` with `az group delete --yes` and waits. It asks separately before `gh repo delete` for each learner repo. Finally removes `progress`.
- [ ] `cost`: month-to-date actual cost via `az consumption usage list` summed with jq, printed as `month to date: X <currency> of budget 300`. If the API is unsupported for the offer, it prints `cost API not available for this subscription type; check the portal` and exits 0.

**Verify:** `bats tests/ops.bats` → all tests pass

**Steps:**
- [ ] Tests: `pause destroys stacks in order and skips missing`, `resume dispatches workflow when present`, `resume applies locally before pipelines exist`, `grade refuses while paused`, `nuke requires typed prefix`, `nuke deletes state RG after stacks`, `cost sums usage`, `cost tolerates unsupported API`. Assert on `$FAKE_LOG` order.
- [ ] Run → FAIL. Implement. Run → PASS. Run shellcheck.
- [ ] Commit `feat: pause, resume, nuke and cost`.

### Task 6: Offline validation and selftest

**Goal:** Tools that prove content is consistent without Azure: track lint, reference validation, and `selftest --offline`. `selftest` (live) is wired up but only run in Task 16.

**Files:**
- Create: `tests/lint-tracks.sh`, `tests/validate-reference.sh`, `lib/selftest.sh`, `tests/selftest.bats`, `.github/workflows/ci.yml`

**Acceptance Criteria:**
- [ ] `lint-tracks.sh [track]` fails on: a missing required file, bad or missing front matter keys, a `requires` id that doesn't exist, `checks.sh` with no `check*` call, shellcheck findings in `checks.sh`/`setup.sh`/`catchup.sh`, CRLF anywhere, unknown template tokens in `reference/`, a resource name in `task.md` not matching the naming table patterns (regex list in the script), any banned SKU string (`AzureFirewall`, `Bastion`, `VpnGw`, `Premium`, `azurerm_kubernetes_cluster`, `azuread_`).
- [ ] `validate-reference.sh <id>` builds the reference with the fixture config, then for every `terraform/*` stack and every module in it: `terraform fmt -check -recursive`, `init -backend=false`, `validate`, `tflint` (azurerm ruleset), `trivy config --severity HIGH,CRITICAL --exit-code 1` (allow-list in `tests/trivy-ignore.yaml` with a reason per entry), and `terraform test` where `tests/` exist (mock providers only). For `ansible/`: `yamllint`, `ansible-lint --profile production`, `ansible-playbook --syntax-check` for every playbook, and `molecule test` for every role with `molecule/` (skip with `--no-molecule`).
- [ ] `lab.sh selftest --offline [track] [--from id] [--to id]`: for each task, build the reference up to the previous task and assert `grade --offline` has ≥ 1 FAIL (skipped for tasks with no `check_code`, listed as `n/a`). Then build up to the task itself and assert all `check_code` pass. Prints a table and exits non-zero on any violation.
- [ ] `lab.sh selftest [track] [--from] [--to]` (live): for each task, `grade` must fail before (`setup.sh` run first), then `catchup <id> --yes`, then `grade` must pass. Stops at the first violation. Requires `SELFTEST_I_HAVE_PERMISSION=1` in the environment.
- [ ] `ci.yml` (harness repo) runs shellcheck, bats, `lint-tracks.sh`, and `validate-reference.sh` for the last task of each track with `--no-molecule`, plus a separate molecule job.

**Verify:** `bats tests/selftest.bats && tests/lint-tracks.sh demo` → pass (demo fixture track)

**Steps:**
- [ ] Tests: `lint catches missing file`, `lint catches unknown token`, `lint catches banned sku`, `selftest offline flags check that passes before task`, `selftest offline flags check that fails after task`, `live selftest refuses without permission variable`.
- [ ] Run → FAIL. Implement. Run → PASS. Run shellcheck.
- [ ] Commit `feat: offline validation and selftest`.

---

**Content tasks (7–15) share one procedure.** For every lab task in the phase:
1. Write `task.md` with front matter, a short story line ("The CTO wants…"), exact deliverables with the expanded names from the naming table, and the target minutes (15–20).
2. Write `hint.md` (2–4 doc links on developer.hashicorp.com / registry / learn.microsoft.com / docs.ansible.com, plus the traps), `solution.md` (approach, key code, how to verify) and `checks.sh` (3–8 checks; a reason for each one).
3. Write `reference/` and, where needed, `setup.sh` (incidents, snapshots) and `catchup.sh` (non-file steps).
4. Run the phase gate: `tests/lint-tracks.sh <track>`, `tests/validate-reference.sh <last id of phase>`, `./lab.sh selftest --offline <track> --from <first> --to <last>` → all pass.
5. Commit `content(<track>): phase <n> — <title>`.

Each task's `**Verify:**` is that phase gate.

### Task 7: Terraform phase 0 — Foundation (tf-01…tf-06)

**Goal:** Tasks tf-01 to tf-06 per the spec's Phase 0, ending with a working PR-plan / merge-apply pipeline and protected `main`.

**Files:**
- Create: `tracks/terraform/README.md` (track intro, chosen VM size, cost notes), `tracks/terraform/01-setup/` … `tracks/terraform/06-protect-main/` (all files per the task directory contract)

**Acceptance Criteria:**
- [ ] tf-01: tool install hints for WSL, `az login`, `./lab.sh init`, `gh repo create {GH_OWNER}/{LIVE_REPO} --public`. Checks: terraform ≥ pinned minor, Linux `az` logged in to `SUBSCRIPTION_ID`, the repo exists and is public, `.gitignore` covers `.terraform/`, `*.tfstate*`, `*.tfvars` except `*.auto.tfvars.example`.
- [ ] tf-02/03: bootstrap stack and state self-migration. Checks include `allowSharedKeyAccess == false`, versioning on, blob `bootstrap.tfstate` exists, no `terraform.tfstate` in git history (`git log --all -- '*.tfstate'` empty), backend uses `use_azuread_auth = true`.
- [ ] tf-04: `id-{P}-github-ci` with federated credentials `gh-main` (`repo:{GH_OWNER}/{LIVE_REPO}:ref:refs/heads/main`), `gh-pr` (`…:pull_request`), `gh-env-prod` (`…:environment:prod`). Roles: Contributor, Role Based Access Control Administrator with a condition limiting assignable roles (AcrPull, Key Vault Secrets User, Reader, Storage Blob Data Contributor), and Storage Blob Data Contributor on the state container.
- [ ] tf-05: workflow `.github/workflows/terraform.yml` with `workflow_dispatch` input `stacks`. The PR job posts the plan as a comment. Checks via `gh api`: the workflow exists, the latest `main` run succeeded, a PR has a comment containing `Terraform plan`, repo variables `AZURE_CLIENT_ID/AZURE_TENANT_ID/AZURE_SUBSCRIPTION_ID` exist, no repo secrets named `ARM_*`/`AZURE_CLIENT_SECRET`.
- [ ] tf-06: ruleset on `main` requiring the plan status check and PRs. Environment `prod` with the learner as required reviewer.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh terraform && tests/validate-reference.sh tf-06 && ./lab.sh selftest --offline terraform --from tf-01 --to tf-06` → all pass

**Steps:** follow the shared content procedure above.

### Task 8: Terraform phase 1 — Landing zone (tf-07…tf-14)

**Goal:** Tasks tf-07 to tf-14 per the spec's Phase 1, ending with separate `landing-zone`, `env-dev` and `env-prod` stacks that read the hub through data sources.

**Files:**
- Create: `tracks/terraform/07-conventions/` … `tracks/terraform/14-split-stacks/`

**Acceptance Criteria:**
- [ ] Names, CIDRs, peering, DNS links, policy, budget and Log Analytics exactly as in the naming table.
- [ ] tf-07 checks (code): `variable "env"` has a validation restricting it to `dev`/`prod`, and a `locals` block builds the tag map with `owner`, `env`, `managed_by`.
- [ ] tf-11 check: creating an untagged RG fails (`az group create -n rg-{P}-policytest … ` must exit non-zero with `RequestDisallowedByPolicy`; the check deletes the group if it was created).
- [ ] tf-12: the budget exists with the amount and thresholds from the table. `solution.md` notes the fallback if the offer type doesn't support budgets (flagged for Task 16).
- [ ] tf-14: state keys `landing-zone.tfstate`, `env-dev.tfstate`, `env-prod.tfstate` exist. A code check confirms no `terraform_remote_state` in `env-*` stacks.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh terraform && tests/validate-reference.sh tf-14 && ./lab.sh selftest --offline terraform --from tf-07 --to tf-14` → all pass

**Steps:** follow the shared content procedure above.

### Task 9: Terraform phase 2 — Modules (tf-15…tf-20)

**Goal:** Tasks tf-15 to tf-20 per the spec's Phase 2, ending with modules in `{MODULES_REPO}`, dev on `v2.0.0`, prod on `v1.x`.

**Files:**
- Create: `tracks/terraform/15-extract-module/` … `tracks/terraform/20-breaking-change/`

**Acceptance Criteria:**
- [ ] tf-15 `setup.sh` snapshots the spoke resource IDs to `$LAB_HOME/snapshots/tf-15.ids` (`az resource list -g rg-{P}-dev --query '[].id'` and the same for prod). A check confirms the IDs are unchanged, plus a code check that `moved` blocks exist.
- [ ] tf-17: `terraform test` files with `mock_provider "azurerm"` run offline in `validate-reference.sh` and in the learner's CI.
- [ ] tf-18: CI runs tflint and trivy. Checks: the workflow contains both steps and the last run succeeded.
- [ ] tf-19: reference `modules/` tree. Checks: tag `v1.0.0` exists in `{MODULES_REPO}` (`gh api repos/{GH_OWNER}/{MODULES_REPO}/git/refs/tags/v1.0.0`), live code sources `git::https://github.com/{GH_OWNER}/{MODULES_REPO}.git//spoke?ref=v1.0.0`, and no `source = "./modules` remains.
- [ ] tf-20: tag `v2.0.0` exists with a renamed variable, `CHANGELOG.md` has a `2.0.0` entry, `env-dev` refs `v2.0.0`, `env-prod` refs `v1.`.
- [ ] `validate-reference.sh` resolves module sources by rewriting `git::https://github.com/{GH_OWNER}/{MODULES_REPO}.git//X?ref=*` to the local reference `modules/X`, so validation stays offline.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh terraform && tests/validate-reference.sh tf-20 && ./lab.sh selftest --offline terraform --from tf-15 --to tf-20` → all pass

**Steps:** follow the shared content procedure above.

### Task 10: Terraform phase 3 — Environments and handover (tf-21…tf-25)

**Goal:** Tasks tf-21 to tf-25 per the spec's Phase 3, ending with the handover state the Ansible track depends on.

**Files:**
- Create: `tracks/terraform/21-app-env-module/` … `tracks/terraform/25-vms-handover/`

**Acceptance Criteria:**
- [ ] Key Vault per Global Constraints (RBAC, 7-day retention, public access enabled, private endpoint `pe-kv-{P}-{env}` in `snet-pe` with a DNS zone group).
- [ ] tf-23: Container App pulls from `acr{P}{S}` via `id-{P}-app-dev` and reads one Key Vault secret reference. Check: `curl -fsS https://<fqdn>/` returns 200 (FQDN from `az containerapp show`).
- [ ] tf-24: the pipeline matrix covers `env-dev`/`env-prod`, and prod apply uses `environment: prod`. Check that the last prod apply job ran in environment `prod`.
- [ ] tf-25: VMs per the naming table. Ubuntu 24.04 LTS, SSH key only (`admin_ssh_key` from var, private key never in the repo). NSG `nsg-{P}-hub-runner` allows 22 only from `{LEARNER_IP}/32`. The jump VM has a system-assigned identity with Reader on the subscription and Key Vault Secrets User on both vaults. Outputs `jump_public_ip`, `web_private_ips`.
- [ ] `tracks/terraform/25-vms-handover/task.md` ends with a "Handover to the Ansible track" section, and `README.md` at the root says the same.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh terraform && tests/validate-reference.sh tf-25 && ./lab.sh selftest --offline terraform --from tf-21 --to tf-25` → all pass

**Steps:** follow the shared content procedure above.

### Task 11: Terraform phase 4 — Day two (tf-26…tf-31)

**Goal:** Tasks tf-26 to tf-31 per the spec's Phase 4, including the injected incidents. Nothing breaks Ansible's dependencies.

**Files:**
- Create: `tracks/terraform/26-import/` … `tracks/terraform/31-self-service/`

**Acceptance Criteria:**
- [ ] Incident `setup.sh` scripts are idempotent and print only the "symptom" (what a teammate would report), never the cause. tf-26 creates `rg-{P}-legacy`/`st{P}legacy{S}` with az. tf-27 removes the `owner` tag from `rg-{P}-dev` and adds an NSG rule `AllowAll-Temp` to `nsg-{P}-dev-app`. tf-28 acquires an infinite blob lease on `env-dev.tfstate` and writes a matching lock-info metadata entry.
- [ ] tf-27: the scheduled workflow `drift.yml` (cron) runs `plan -detailed-exitcode` per stack and opens an issue labelled `drift` on exit 2. Checks: the workflow exists with `schedule`, an issue labelled `drift` exists, and a fresh plan of `env-dev` is clean.
- [ ] tf-28 check: the blob lease state is `available`, and `terraform plan` on `env-dev` succeeds in CI after the task start time.
- [ ] tf-29 check: the Log Analytics resource ID is unchanged (snapshot), it's in `observability.tfstate`, and it's not in `landing-zone.tfstate` (read state via `az storage blob download` + jq).
- [ ] tf-30: `.terraform.lock.hcl` has `h1:` hashes for `linux_amd64` and `windows_amd64`, and `.github/dependabot.yml` (or `renovate.json`) covers terraform providers and module refs.
- [ ] tf-31: one `module "team_payments"` call in `terraform/teams/payments` producing the day-two team resources from the naming table, a federated credential for `repo:{GH_OWNER}/payments-app:ref:refs/heads/main`, and a budget of 100.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh terraform && tests/validate-reference.sh tf-31 && ./lab.sh selftest --offline terraform --from tf-26 --to tf-31` → all pass

**Steps:** follow the shared content procedure above.

### Task 12: Ansible phase A — Foundation (an-01…an-05)

**Goal:** Tasks an-01 to an-05 per the spec's Phase A, pitched intermediate/advanced.

**Files:**
- Create: `tracks/ansible/README.md` (intro, assumes tf-25 or `./lab.sh catchup tf-25`), `tracks/ansible/01-layout/` … `tracks/ansible/05-molecule/`

**Acceptance Criteria:**
- [ ] All `an-*` task.md front matter `requires` includes `tf-25`.
- [ ] an-01: `ansible/requirements.txt` pins `ansible-core`, `ansible/collections/requirements.yml` pins `azure.azcollection`, `community.general`, `ansible.posix` by exact version, `.venv/` gitignored.
- [ ] an-02: inventory `ansible/inventory/azure_rm.yml` with `keyed_groups` on tags `role` and `env`, `ansible_ssh_common_args` ProxyJump via the jump host's public IP (looked up dynamically, never hard-coded). Checks: `ansible-inventory --graph` contains `@role_web` and `@env_dev`, and `ansible all -m ping` succeeds.
- [ ] an-03: role `base` (users, sshd hardening, unattended-upgrades, chrony). Checks over SSH: `sshd -T` shows `passwordauthentication no` and `permitrootlogin no`, and a second playbook run reports `changed=0` on all hosts.
- [ ] an-04/an-05: ansible-lint production profile clean, pre-commit config present, and `molecule test` for `base` passes in `validate-reference.sh`.
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh ansible && tests/validate-reference.sh an-05 && ./lab.sh selftest --offline ansible --from an-01 --to an-05` → all pass

**Steps:** follow the shared content procedure above.

### Task 13: Ansible phase B — Services (an-06…an-10)

**Goal:** Tasks an-06 to an-10 per the spec's Phase B.

**Files:**
- Create: `tracks/ansible/06-nginx/` … `tracks/ansible/10-haproxy/`

**Acceptance Criteria:**
- [ ] an-07: a secret `app-greeting` in `kv-{P}-dev-{S}` (created by the task's `setup.sh` with a random value, and by `catchup.sh`) ends up in `/etc/acme/app.env` on the web VMs. Check: `git grep` over the learner repo for the value is empty.
- [ ] an-08: certificate `web-tls` (self-signed, Key Vault policy) is served on 443. Check: `openssl s_client` through the jump host returns that cert's thumbprint.
- [ ] an-09: app `acme-hello` (tiny Python http.server-based app shipped in the role's `files/`, version in `app_version` var) runs as systemd unit `acme-hello.service`, with a `/health` endpoint returning `ok <version>`.
- [ ] an-10: HAProxy on the jump VM, frontend :80 → backend `web` with both web VMs. Admin socket at `/run/haproxy/admin.sock` (used in an-11). Check: 10 requests through the jump IP hit both backends (the response contains the hostname).
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh ansible && tests/validate-reference.sh an-10 && ./lab.sh selftest --offline ansible --from an-06 --to an-10` → all pass

**Steps:** follow the shared content procedure above.

### Task 14: Ansible phase C — Operations (an-11…an-20)

**Goal:** Tasks an-11 to an-20 per the spec's Phase C (an-21 moves to `cap-01`).

**Files:**
- Create: `tracks/ansible/11-rolling-update/` … `tracks/ansible/20-compliance-report/`

**Acceptance Criteria:**
- [ ] an-11 check: the grader starts `curl` through the jump IP every 0.2 s in the background, runs `ansible-playbook rolling.yml -e app_version=2.0.0`, and requires 0 failed requests and `/health` = `ok 2.0.0` on both VMs. A code check confirms `serial` and `delegate_to` against the HAProxy host.
- [ ] an-12 `setup.sh` edits `/etc/nginx/nginx.conf` (`worker_connections 1`) and stops nginx on `vm-{P}-web-dev-2`. Checks: `ansible.yml` has a `schedule` job running `--check --diff`, and both hosts are compliant again.
- [ ] an-15/an-16: the runner on `vm-{P}-jump` registers with labels `self-hosted,acme-jump`. Hardening checks via `gh api`: fork-PR approval set to `all_external_contributors`, and the workflow's runner jobs carry `if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name != 'pull_request'`. Azure login on the runner uses the VM's managed identity, and the repo has no secrets.
- [ ] an-18 check: the grader runs `deploy.yml -e app_version=broken` (a version whose `/health` fails, shipped in the role) and asserts the playbook exits non-zero and both VMs still serve the previous version.
- [ ] an-19: running against prod without `-e confirm_prod=true` fails on an `assert`. Inventory group `env_prod` exists (prod VMs aren't created; the check uses `--list-hosts` + `assert` behaviour with a fixture inventory).
- [ ] Phase gate passes.

**Verify:** `tests/lint-tracks.sh ansible && tests/validate-reference.sh an-20 && ./lab.sh selftest --offline ansible --from an-11 --to an-20` → all pass

**Steps:** follow the shared content procedure above.

### Task 15: Joint capstone, README and docs

**Goal:** The cross-track capstone `cap-01` plus learner-facing docs in the same style as ckad-practice.

**Files:**
- Create: `tracks/capstone/01-rebuild/`, modify `README.md`

**Acceptance Criteria:**
- [ ] `cap-01` requires `tf-31` and `an-20`. `setup.sh` deletes `vm-{P}-web-dev-2` and its OS disk/NIC with az. The learner must make the Terraform pipeline recreate it and trigger `ansible.yml` (`workflow_run` or `repository_dispatch`), so the VM rejoins the HAProxy pool without manual commands. Checks: the VM exists, the latest `ansible.yml` run was triggered by `workflow_run`/`repository_dispatch`, both backends answer through HAProxy, and `grade --all` across all tracks reports no regressions.
- [ ] `README.md`: what it is, prerequisites (WSL), the command table, the cost model and the "always `./lab.sh pause` when you stop" rule, track order, catchup semantics (backup branch), and the public-repo note. Under 120 lines, written in the tone of ckad-practice's README.
- [ ] Phase gate for `capstone` passes, and `tests/lint-tracks.sh` (all tracks) passes.

**Verify:** `tests/lint-tracks.sh && tests/validate-reference.sh cap-01 && ./lab.sh selftest --offline capstone` → all pass

**Steps:** follow the shared content procedure above.

### Task 16: Live selftest against Azure (blocked on learner permission)

**Goal:** Prove every grader fails before its task and passes after, against the real Visual Studio subscription, and fix what breaks.

**Files:**
- Modify: any `tracks/**` file whose live behaviour differs, `tracks/terraform/README.md` (verified VM size, budget support)

**Acceptance Criteria:**
- [ ] Not started until the learner explicitly says Claude may use the subscription in this session.
- [ ] `SELFTEST_I_HAVE_PERMISSION=1 ./lab.sh selftest` passes for terraform, ansible and capstone.
- [ ] `./lab.sh cost` after the run is reported to the learner, and `./lab.sh nuke` leaves no `rg-{P}-*` groups (`az group list --query "[?starts_with(name,'rg-$PREFIX-')]"` empty).

**Verify:** `SELFTEST_I_HAVE_PERMISSION=1 ./lab.sh selftest && ./lab.sh nuke && az group list --query "[?starts_with(name,'rg-$PREFIX-')].name" -o tsv` → selftest table all ✓, then empty group list after nuke

**Steps:**
- [ ] Ask the learner for permission. Wait.
- [ ] `./lab.sh init` with a throwaway GitHub owner/repo prefix agreed with the learner (e.g. `PREFIX=lab`), so selftest repos don't collide with the learner's own `acme-*` repos.
- [ ] Run selftest per track, fix graders/reference, re-run, commit `fix(<track>): live selftest corrections`.
- [ ] `./lab.sh nuke`, then report the cost.
