load test_helper

setup() {
  setup_lab
  export TRACKS_DIR="$REPO_ROOT/tests/fixtures/catchuptracks"
  export WINDOWS_MOUNT_PREFIX="$TEST_TMP/no-windows/"
  export NO_COLOR=1
  export HOOK_LOG="$TEST_TMP/hooks.log"
  : >"$HOOK_LOG"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  LAB="$REPO_ROOT/lab.sh"
  make_repo "$TEST_TMP/acme/acme-platform" "$TEST_TMP/remote-live.git"
  make_repo "$TEST_TMP/acme/acme-terraform-modules" "$TEST_TMP/remote-mod.git"
}
teardown() { teardown_lab; }

make_repo() { # make_repo <dir> <bare>
  git init -q --bare -b main "$2"
  rm -rf "$1"
  git init -q -b main "$1"
  git -C "$1" remote add origin "$2"
  echo mine >"$1/mine.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m learner
  git -C "$1" push -q origin main
}

LIVE() { echo "$TEST_TMP/acme/acme-platform"; }

render_env() {
  export PREFIX=acme GH_OWNER=learner SUBSCRIPTION_ID=sub-1 LIVE_REPO=acme-platform
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/template.sh"
}

source_libs() {
  set -a
  # shellcheck disable=SC1091
  source "$LAB_HOME/config.env"
  set +a
  for l in common tasks template catchup; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/$l.sh"
  done
}

@test "render replaces known tokens" {
  render_env
  mkdir -p "$TEST_TMP/src/d"
  printf 'a={{PREFIX}} b={{GH_OWNER}}/{{LIVE_REPO}}\n' >"$TEST_TMP/src/d/f.txt"
  printf '\x00\x01{{PREFIX}}\x00' >"$TEST_TMP/src/bin.dat"
  : >"$TEST_TMP/src/empty"
  run render_tree "$TEST_TMP/src" "$TEST_TMP/dst"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMP/dst/d/f.txt")" = "a=acme b=learner/acme-platform" ]
  cmp "$TEST_TMP/src/bin.dat" "$TEST_TMP/dst/bin.dat"
  [ -f "$TEST_TMP/dst/empty" ]
}

@test "render rejects unknown token" {
  render_env
  mkdir -p "$TEST_TMP/src"
  printf 'x={{PREFIX}} y={{NOPE}}\n' >"$TEST_TMP/src/bad.tf"
  run render_tree "$TEST_TMP/src" "$TEST_TMP/dst"
  [ "$status" -eq 5 ]
  [[ "$output" == *"bad.tf"* && "$output" == *"{{NOPE}}"* ]]
}

@test "replay applies overlays and deletes" {
  set -a
  # shellcheck disable=SC1091
  source "$LAB_HOME/config.env"
  set +a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/tasks.sh"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/template.sh"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/catchup.sh"
  build_reference tf-25 "$TEST_TMP/out"
  [ "$(cat "$TEST_TMP/out/live/README.md")" = "prefix=acme owner=learner sub=00000000-0000-0000-0000-000000000000" ]
  [ ! -e "$TEST_TMP/out/live/old.txt" ]
  [ -f "$TEST_TMP/out/live/terraform/main.tf" ]
  [ -f "$TEST_TMP/out/live/terraform/late.tf" ]
  [ "$(cat "$TEST_TMP/out/modules/m.tf")" = "module acme" ]
  build_reference tf-02 "$TEST_TMP/out2"
  [ ! -e "$TEST_TMP/out2/live/terraform/late.tf" ]
  [ ! -e "$TEST_TMP/out2/modules" ]
  build_reference an-01 "$TEST_TMP/out3"
  [ -f "$TEST_TMP/out3/live/terraform/late.tf" ]
  [ -f "$TEST_TMP/out3/live/ansible/site.yml" ]
  [ ! -e "$TEST_TMP/out3/live/ansible/roles.yml" ]
}

@test "catchup refuses dirty tree" {
  echo dirty >"$(LIVE)/untracked.txt"
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [[ "$output" == *"uncommitted changes in $(LIVE) — commit or stash first"* ]]
  [ -f "$(LIVE)/mine.txt" ]
}

@test "catchup backs up main to my-work branch" {
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 0 ]
  b="$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*' --format '%(refname:short)' | head -1)"
  [[ "$b" =~ ^my-work/[0-9]{8}-[0-9]{6}$ ]]
  git -C "$TEST_TMP/remote-live.git" show "$b:mine.txt" | grep -q mine
  git -C "$(LIVE)" show-ref --verify -q "refs/heads/$b"
}

@test "catchup result equals reference tree" {
  run "$LAB" catchup --yes tf-25
  [ "$status" -eq 0 ]
  [ ! -e "$(LIVE)/mine.txt" ]
  [ ! -e "$(LIVE)/old.txt" ]
  [ "$(git -C "$(LIVE)" log -1 --format=%s)" = "catchup: tf-25" ]
  [ -z "$(git -C "$(LIVE)" status --porcelain)" ]
  [ "$(git -C "$TEST_TMP/remote-live.git" rev-parse main)" = "$(git -C "$(LIVE)" rev-parse main)" ]
  [ "$(cat "$TEST_TMP/acme/acme-terraform-modules/m.tf")" = "module acme" ]
  [ ! -e "$TEST_TMP/acme/acme-terraform-modules/mine.txt" ]
  [ "$(git -C "$TEST_TMP/remote-mod.git" rev-parse main)" = "$(git -C "$TEST_TMP/acme/acme-terraform-modules" rev-parse main)" ]
  [ ! -d "$(LIVE)/modules" ]
}

@test "catchup asks and aborts on anything but y" {
  run bash -c "echo n | '$LAB' catchup tf-02"
  [ "$status" -eq 6 ]
  [ -f "$(LIVE)/mine.txt" ]
  [ -n "$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*')" ]
  run bash -c "echo y | '$LAB' catchup tf-02"
  [ "$status" -eq 0 ]
  [ ! -e "$(LIVE)/mine.txt" ]
}

@test "catchup without a repo exits 6" {
  rm -rf "$(LIVE)/.git"
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [[ "$output" == *"tf-01"* ]]
}

@test "catchup runs task catchup.sh in order" {
  run "$LAB" catchup --yes tf-25
  [ "$status" -eq 0 ]
  run cat "$HOOK_LOG"
  [ "${lines[0]}" = "tf-01 after-push acme-platform" ]
  [ "${lines[1]}" = "tf-02 after-push acme-platform" ]
  [ "${lines[2]}" = "tf-25 after-push acme-platform" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "creates-repo hook also runs after the push" {
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 0 ]
  grep -qx "tf-01 after-push acme-platform" "$HOOK_LOG"
}

@test "creates-repo hook skipped when repo exists" {
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 0 ]
  ! grep -q before-replace "$HOOK_LOG"
}

@test "creates-repo hook runs before replace when repo is missing" {
  rm -rf "$(LIVE)/.git"
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [ "$(cat "$HOOK_LOG")" = "tf-01 before-replace acme-platform" ]
}

@test "failing catchup.sh stops with exit 1 naming the task" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  echo 'exit 1' >"$TEST_TMP/tracks/terraform/02-main/catchup.sh"
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" catchup --yes tf-25
  [ "$status" -eq 1 ]
  [[ "$output" == *"tf-02"* ]]
}

@test "ansible catchup skips terraform when tf-25 passes" {
  mkdir -p "$(LIVE)/terraform" "$(LIVE)/ansible" "$(LIVE)/.github/workflows"
  echo mine >"$(LIVE)/terraform/late.tf"
  echo keep >"$(LIVE)/terraform/extra.tf"
  echo learner >"$(LIVE)/ansible/own.yml"
  echo learner >"$(LIVE)/.github/workflows/ansible-old.yml"
  echo learner >"$(LIVE)/.github/workflows/terraform.yml"
  git -C "$(LIVE)" add -A
  git -C "$(LIVE)" commit -q -m work
  run "$LAB" catchup --yes an-02
  [ "$status" -eq 0 ]
  [ "$(cat "$(LIVE)/terraform/late.tf")" = "mine" ]
  [ -f "$(LIVE)/terraform/extra.tf" ]
  [ -f "$(LIVE)/mine.txt" ]
  [ -f "$(LIVE)/.github/workflows/terraform.yml" ]
  [ ! -e "$(LIVE)/ansible/own.yml" ]
  [ ! -e "$(LIVE)/.github/workflows/ansible-old.yml" ]
  [ -f "$(LIVE)/ansible/site.yml" ]
  [ -f "$(LIVE)/ansible/roles.yml" ]
  [ -f "$(LIVE)/.github/workflows/ansible-ci.yml" ]
  [ "$(git -C "$(LIVE)" log -1 --format=%s)" = "catchup: an-02" ]
  run cat "$HOOK_LOG"
  [ "${lines[0]}" = "an-01 after-push acme-platform" ]
  [ "${lines[1]}" = "an-02 after-push acme-platform" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "ansible catchup replays terraform first when tf-25 fails" {
  run "$LAB" catchup --yes an-01
  [ "$status" -eq 0 ]
  [ -f "$(LIVE)/terraform/late.tf" ]
  [ -f "$(LIVE)/ansible/site.yml" ]
  [ ! -e "$(LIVE)/mine.txt" ]
  [ "$(git -C "$(LIVE)" log -1 --format=%s)" = "catchup: an-01" ]
  run cat "$HOOK_LOG"
  [ "${lines[0]}" = "tf-01 after-push acme-platform" ]
  [ "${lines[1]}" = "tf-02 after-push acme-platform" ]
  [ "${lines[2]}" = "tf-25 after-push acme-platform" ]
  [ "${lines[3]}" = "an-01 after-push acme-platform" ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*' | wc -l)" -eq 2 ]
}

@test "ansible catchup aborts when tf-25 cannot be graded" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  echo 'check "cloud" true "never"' >"$TEST_TMP/tracks/terraform/03-late/checks.sh"
  # no fake az login response: preflight exits 4
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" catchup --yes an-01
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot check tf-25 state"* ]]
  [ -f "$(LIVE)/mine.txt" ]
  [ -z "$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*')" ]
}

@test "capstone catchup builds full reference" {
  source_libs
  build_reference cap-01 "$TEST_TMP/outc"
  [ -f "$TEST_TMP/outc/live/terraform/late.tf" ]
  [ -f "$TEST_TMP/outc/live/ansible/roles.yml" ]
  [ -f "$TEST_TMP/outc/live/cap.txt" ]
  run "$LAB" catchup --yes cap-01
  [ "$status" -eq 0 ]
  [ ! -e "$(LIVE)/mine.txt" ]
  [ -f "$(LIVE)/cap.txt" ]
  [ -f "$(LIVE)/ansible/roles.yml" ]
  [ "$(git -C "$(LIVE)" log -1 --format=%s)" = "catchup: cap-01" ]
  [ -f "$TEST_TMP/acme/acme-terraform-modules/m.tf" ]
}

@test "catchup refuses when local main is behind origin" {
  other="$TEST_TMP/other"
  git clone -q "$TEST_TMP/remote-live.git" "$other"
  echo merged >"$other/merged.txt"
  git -C "$other" add -A
  git -C "$other" commit -q -m "merged PR"
  git -C "$other" push -q origin main
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [[ "$output" == *"pull/merge first"* ]]
  git -C "$TEST_TMP/remote-live.git" show main:merged.txt
  [ -z "$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*')" ]
}

@test "catchup refuses without local main" {
  rm -rf "$(LIVE)"
  git init -q -b main "$(LIVE)"
  git -C "$(LIVE)" remote add origin "$TEST_TMP/remote-live.git"
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [[ "$output" == *"no local main"* ]]
  git -C "$TEST_TMP/remote-live.git" show main:mine.txt
}

@test "catchup refuses when not on main" {
  git -C "$(LIVE)" checkout -q -b feature
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 6 ]
  [[ "$output" == *"switch to main first (currently on feature)"* ]]
  [ "$(git -C "$(LIVE)" rev-parse main)" = "$(git -C "$(LIVE)" rev-parse feature)" ]
  [ -f "$(LIVE)/mine.txt" ]
}

@test "force push uses lease on verified sha" {
  real_git="$(command -v git)"
  other="$TEST_TMP/other"
  git clone -q "$TEST_TMP/remote-live.git" "$other"
  mkdir -p "$TEST_TMP/gitwrap"
  cat >"$TEST_TMP/gitwrap/git" <<WRAP
#!/usr/bin/env bash
case "\$*" in
  *--force-with-lease=main:*)
    verified="\$(printf '%s
' "\$@" | sed -n 's/^--force-with-lease=main://p')"
    echo "\$verified" >"$TEST_TMP/lease.arg"
    echo racing >"$other/race.txt"
    $real_git -C "$other" add -A
    $real_git -C "$other" commit -q -m race
    $real_git -C "$other" push -q origin main
    ;;
esac
exec $real_git "\$@"
WRAP
  chmod +x "$TEST_TMP/gitwrap/git"
  expected="$(git -C "$TEST_TMP/remote-live.git" rev-parse main)"
  PATH="$TEST_TMP/gitwrap:$PATH" run "$LAB" catchup --yes tf-02
  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_TMP/lease.arg")" = "$expected" ]
  git -C "$TEST_TMP/remote-live.git" show main:race.txt
}

# --- modules repo release tags (tracks/terraform/lib/modules-tag.sh, tf-19/tf-20 catchup) ---

# tag_env: the real terraform track, config exported, MODULES_DIR main = tf-20's modules tree.
tag_env() {
  export TRACKS_DIR="$REPO_ROOT/tracks" LAB_ROOT="$REPO_ROOT"
  set -a
  # shellcheck disable=SC1091
  source "$LAB_HOME/config.env"
  set +a
  MODS="$TEST_TMP/acme/acme-terraform-modules"
  (
    for l in common tasks template catchup; do
      # shellcheck disable=SC1090
      source "$REPO_ROOT/lib/$l.sh"
    done
    build_reference tf-20 "$TEST_TMP/ref20"
  )
  git -C "$MODS" rm -qrf .
  cp -a "$TEST_TMP/ref20/modules/." "$MODS/"
  git -C "$MODS" add -A
  git -C "$MODS" commit -qm "catchup: tf-20"
  git -C "$MODS" push -q origin main
}

MT='source "$REPO_ROOT/tracks/terraform/lib/modules-tag.sh"'

@test "modules_tag tags each release at its own reference tree" {
  tag_env
  run bash -c "$MT && modules_tag v1.0.0 && modules_tag v2.0.0"
  echo "$output"
  [ "$status" -eq 0 ]
  git -C "$TEST_TMP/remote-mod.git" show v1.0.0:spoke/variables.tf | grep -q 'variable "address_space"'
  git -C "$TEST_TMP/remote-mod.git" show v2.0.0:spoke/variables.tf | grep -q 'variable "vnet_cidr"'
  [ "$(git -C "$TEST_TMP/remote-mod.git" rev-parse 'v2.0.0^{commit}')" = "$(git -C "$TEST_TMP/remote-mod.git" rev-parse main)" ]
  run bash -c "$MT && modules_tag v1.0.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already holds the reference module"* ]]
  [[ "$output" != *WARNING* ]]
}

@test "modules_tag warns, saves and moves a pushed tag with other content" {
  tag_env
  git -C "$MODS" tag -a v1.0.0 -m mine HEAD~1
  git -C "$MODS" push -q origin v1.0.0
  run bash -c "$MT && modules_tag v1.0.0"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: your pushed tag v1.0.0"*"my-work/tag-v1.0.0-"* ]]
  git -C "$TEST_TMP/remote-mod.git" show v1.0.0:spoke/variables.tf | grep -q 'variable "address_space"'
  [ -n "$(git -C "$TEST_TMP/remote-mod.git" branch --list 'my-work/tag-v1.0.0-*')" ]
}

@test "modules_tag keeps the learner's tag when the prompt is declined" {
  tag_env
  git -C "$MODS" tag -a v1.0.0 -m mine HEAD~1
  git -C "$MODS" push -q origin v1.0.0
  mine="$(git -C "$TEST_TMP/remote-mod.git" rev-parse 'v1.0.0^{commit}')"
  run bash -c "echo n | MODULES_TAG_PROMPT=1 bash -c '$MT && modules_tag v1.0.0'"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept your v1.0.0"* ]]
  [ "$(git -C "$TEST_TMP/remote-mod.git" rev-parse 'v1.0.0^{commit}')" = "$mine" ]
  [ -z "$(git -C "$TEST_TMP/remote-mod.git" branch --list 'my-work/tag-*')" ]
  # catchup --yes never asks
  run bash -c "echo n | MODULES_TAG_PROMPT=1 CATCHUP_YES=1 bash -c '$MT && modules_tag v1.0.0'"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_TMP/remote-mod.git" rev-parse 'v1.0.0^{commit}')" != "$mine" ]
}

@test "modules_tag backs up a local-only tag before overwriting it" {
  tag_env
  git -C "$MODS" tag -a v1.0.0 -m mine-local HEAD~1
  mine="$(git -C "$MODS" rev-parse 'v1.0.0^{commit}')"
  run bash -c "$MT && modules_tag v1.0.0"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: your local (unpushed) tag v1.0.0"* ]]
  b="$(git -C "$MODS" branch --list 'my-work/tag-v1.0.0-*-local' | tr -d ' *')"
  [ -n "$b" ]
  [ "$(git -C "$MODS" rev-parse "$b")" = "$mine" ]
  git -C "$TEST_TMP/remote-mod.git" show v1.0.0:spoke/variables.tf | grep -q 'variable "address_space"'
}

@test "modules_tag_pinned tags exactly the pinned releases and fails on unknown ones" {
  tag_env
  mkdir -p "$(LIVE)/terraform/env-prod" "$(LIVE)/terraform/env-dev"
  printf 'module "spoke" {\n  source = "git::https://github.com/learner/acme-terraform-modules.git//spoke?ref=v1.0.0"\n}\n' \
    >"$(LIVE)/terraform/env-prod/main.tf"
  run bash -c 'cd "$1" && eval "$2" && modules_tag_pinned' _ "$(LIVE)" "$MT"
  echo "$output"
  [ "$status" -eq 0 ]
  git -C "$TEST_TMP/remote-mod.git" rev-parse -q --verify refs/tags/v1.0.0
  ! git -C "$TEST_TMP/remote-mod.git" rev-parse -q --verify refs/tags/v2.0.0
  printf 'module "spoke" {\n  source = "git::https://github.com/learner/acme-terraform-modules.git//spoke?ref=v1.1.0"\n}\n' \
    >"$(LIVE)/terraform/env-dev/main.tf"
  run bash -c 'cd "$1" && eval "$2" && modules_tag_pinned' _ "$(LIVE)" "$MT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"v1.1.0 is not a known module release"*"module-releases.txt"* ]]
}

# --- tf-17/tf-18 live check: PR run green, or a newer green catchup run on main -------------

# ci_case <pr runs json> <main runs json>: runs ci_pr_green_or_caught_up against a gh stub that
# applies the --jq filter to the canned API answer.
# PR_FILES maps PR numbers to their changed files ("7:terraform/main.tf 8:README.md"): runs whose
# PR changed no Terraform path are no-ops (tf-24's change filter) and don't count.
ci_case() {
  PR_JSON=$1 MAIN_JSON=$2 PR_FILES=${3:-} run bash -c '
    gh() {
      if [[ "$2" == --paginate && "$3" == */pulls/*/files* ]]; then
        local n f out=""
        n=${3%/files*}; n=${n##*/}
        for f in $PR_FILES; do [[ "${f%%:*}" == "$n" ]] && out+="${f#*:}"$'"'"'\n'"'"'; done
        printf "%s" "$out"
        return 0
      fi
      case "$2" in
        *event=pull_request*) jq -r "$4" <<<"$PR_JSON" ;;
        *) jq -c "$4" <<<"$MAIN_JSON" ;;
      esac
    }
    source "$REPO_ROOT/tracks/terraform/lib/ci-runs.sh"
    ci_pr_green_or_caught_up learner/acme-platform'
}
run_json() { # run_json <conclusion> <created_at> [message] [id]
  printf '{"workflow_runs":[{"id":%s,"conclusion":"%s","created_at":"%s","head_commit":{"message":"%s"}}]}' "${4:-1}" "$1" "$2" "${3:-x}"
}

@test "ci check passes on a green PR run" {
  ci_case "$(run_json success 2026-11-23T10:00:00Z)" "$(run_json failure 2026-11-23T11:00:00Z)"
  [ "$status" -eq 0 ]
}

@test "ci check passes on a newer green catchup run on main after a red PR run" {
  ci_case "$(run_json failure 2026-11-23T10:00:00Z)" "$(run_json success 2026-11-23T11:00:00Z 'catchup: tf-18')"
  [ "$status" -eq 0 ]
  ci_case '{"workflow_runs":[]}' "$(run_json success 2026-11-23T11:00:00Z 'catchup: tf-18')"
  [ "$status" -eq 0 ]
}

@test "ci check fails on a red PR run without a newer catchup run" {
  ci_case "$(run_json failure 2026-11-23T10:00:00Z)" "$(run_json success 2026-11-23T11:00:00Z 'Merge pull request #7')"
  [ "$status" -ne 0 ]
  ci_case "$(run_json failure 2026-11-23T12:00:00Z)" "$(run_json success 2026-11-23T11:00:00Z 'catchup: tf-18')"
  [ "$status" -ne 0 ]
  ci_case "$(run_json failure 2026-11-23T10:00:00Z)" "$(run_json failure 2026-11-23T11:00:00Z 'catchup: tf-18')"
  [ "$status" -ne 0 ]
}

pr_runs() { # pr_runs "<id> <conclusion> <created_at> <pr number>"...: a runs list, newest first
  local r out="" id c t n
  for r in "$@"; do
    read -r id c t n <<<"$r"
    out+="${out:+,}{\"id\":$id,\"conclusion\":\"$c\",\"created_at\":\"$t\",\"pull_requests\":[{\"number\":$n}]}"
  done
  printf '{"workflow_runs":[%s]}' "$out"
}

@test "ci check: a green PR run for a Terraform change passes, whatever its steps are called" {
  # e.g. unnamed "- run: terraform fmt -check" steps (GitHub calls them "Run terraform ...")
  ci_case "$(pr_runs "9 success 2026-11-23T12:00:00Z 7")" "$(run_json failure 2026-11-23T11:00:00Z)" "7:terraform/landing-zone/main.tf"
  [ "$status" -eq 0 ]
}

@test "ci check: a PR run that failed (say at fmt) fails, even with an older green one" {
  ci_case "$(pr_runs "9 failure 2026-11-23T12:00:00Z 7" "8 success 2026-11-23T10:00:00Z 6")" \
    "$(run_json success 2026-11-23T11:00:00Z 'Merge pull request #6')" "7:terraform/landing-zone/main.tf 6:terraform/env-dev/main.tf"
  [ "$status" -ne 0 ]
}

@test "ci check ignores runs of PRs that changed no Terraform path (tf-24 change filter)" {
  runs="$(pr_runs "9 success 2026-11-23T12:00:00Z 7" "8 failure 2026-11-23T10:00:00Z 6")"
  ci_case "$runs" "$(run_json success 2026-11-23T11:00:00Z 'Merge pull request #7')" "7:README.md 6:terraform/env-dev/main.tf"
  [ "$status" -ne 0 ]
  runs="$(pr_runs "9 success 2026-11-23T12:00:00Z 7" "8 success 2026-11-23T10:00:00Z 6")"
  ci_case "$runs" "$(run_json failure 2026-11-23T11:00:00Z)" "7:README.md 6:.github/workflows/terraform.yml"
  [ "$status" -eq 0 ]
}

# --- ci_main_green / ci_applied_since: only runs whose apply job ran count ----------------------
main_case() { # main_case <runs json> <jobs per run: "id:conclusion ..."> <function call>
  RUNS_JSON=$1 APPLY=$2 run bash -c '
    gh() {
      case "$2" in
        */jobs*) local id c=none a; id=${2%/jobs*}; id=${id##*/}
          for a in $APPLY; do [[ "${a%%:*}" == "$id" ]] && c=${a#*:}; done
          jq -r "$4" <<<"{\"jobs\":[{\"name\":\"apply\",\"conclusion\":\"$c\"}]}" ;;
        *) jq -r "$4" <<<"$RUNS_JSON" ;;
      esac
    }
    source "$REPO_ROOT/tracks/terraform/lib/ci-runs.sh"
    '"$3"
}

@test "ci_main_green skips green runs without an apply and judges the newest one that applied" {
  runs='{"workflow_runs":[{"id":3,"conclusion":"success"},{"id":2,"conclusion":"success"},{"id":1,"conclusion":"failure"}]}'
  main_case "$runs" "3:skipped 2:success 1:failure" "ci_main_green o/r"
  [ "$status" -eq 0 ]
  main_case "$runs" "3:skipped 2:skipped 1:failure" "ci_main_green o/r"
  [ "$status" -ne 0 ]
  runs='{"workflow_runs":[{"id":3,"conclusion":"failure"},{"id":2,"conclusion":"success"}]}'
  main_case "$runs" "3:skipped 2:success" "ci_main_green o/r"
  [ "$status" -ne 0 ]
}

@test "ci_applied_since wants a green run whose apply job ran" {
  runs='{"workflow_runs":[{"id":5},{"id":4}]}'
  main_case "$runs" "5:skipped 4:success" "ci_applied_since o/r 0"
  [ "$status" -eq 0 ]
  main_case "$runs" "5:skipped 4:skipped" "ci_applied_since o/r 0"
  [ "$status" -ne 0 ]
}

# finished_ids: the ids with a finish time in the progress file, space separated.
finished_ids() { awk -F'\t' '$3 != "" { printf "%s ", $1 }' "$LAB_HOME/progress"; }

@test "catchup marks the replayed tasks done, keeping recorded start times" {
  printf 'tf-01\t5\t\n' >"$LAB_HOME/progress"
  run "$LAB" catchup --yes tf-25
  [ "$status" -eq 0 ]
  [ "$(finished_ids)" = "tf-01 tf-02 tf-25 " ]
  grep -qP '^tf-01\t5\t\d+$' "$LAB_HOME/progress"
  run "$LAB" next terraform
  [[ "$output" == *"all tasks in terraform done"* ]]
  run "$LAB" next ansible
  [ "$status" -eq 0 ]
  grep -qP '^an-01\t\d+\t$' "$LAB_HOME/progress"
}

@test "ansible catchup marks tf-25 done when its checks pass, and the replayed Ansible tasks" {
  mkdir -p "$(LIVE)/terraform"
  echo mine >"$(LIVE)/terraform/late.tf"
  git -C "$(LIVE)" add -A
  git -C "$(LIVE)" commit -q -m work
  run "$LAB" catchup --yes an-02
  [ "$status" -eq 0 ]
  [ "$(finished_ids)" = "tf-25 an-01 an-02 " ]
}

@test "a failed catchup marks nothing done" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  echo 'exit 1' >"$TEST_TMP/tracks/terraform/03-late/catchup.sh"
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" catchup --yes tf-25
  [ "$status" -eq 1 ]
  [ -z "$(finished_ids 2>/dev/null)" ]
}

# --- final review fix wave: catchup ------------------------------------------------------------

no_backup() { [ -z "$(git -C "$TEST_TMP/remote-live.git" branch --list 'my-work/*')" ]; }

@test "C1: ansible catchup never replays tf-25 over a finished tf-26+ task; prints the failing checks" {
  printf 'tf-26\t1\t2\n' >"$LAB_HOME/progress"
  run "$LAB" catchup --yes an-01
  echo "$output"
  [ "$status" -eq 6 ]
  [[ "$output" == *"FAIL  late present"* ]]
  [[ "$output" == *"terraform/late.tf is missing"* ]]
  [[ "$output" == *"tf-26 is done"* ]]
  [[ "$output" != *"replaying the Terraform reference"* ]]
  [ -f "$(LIVE)/mine.txt" ]
  no_backup
  [ ! -s "$HOOK_LOG" ]
}

@test "C1: ansible catchup never replays tf-25 when terraform/observability or terraform/teams exists" {
  for s in observability teams/payments; do
    mkdir -p "$(LIVE)/terraform/$s"
    echo 'x' >"$(LIVE)/terraform/$s/main.tf"
    git -C "$(LIVE)" add -A
    git -C "$(LIVE)" commit -q -m "$s"
    git -C "$(LIVE)" push -q origin main
    run "$LAB" catchup --yes an-01
    [ "$status" -eq 6 ]
    [[ "$output" == *"terraform/${s%%/*} exists"* ]]
    [ -f "$(LIVE)/terraform/$s/main.tf" ]
    no_backup
    git -C "$(LIVE)" rm -rqf "terraform/${s%%/*}"
    git -C "$(LIVE)" commit -q -m "rm $s"
    git -C "$(LIVE)" push -q origin main
  done
}

@test "C1: ansible catchup doesn't replay terraform when tf-25's checks.sh fails to load" {
  cp -r "$TRACKS_DIR" "$TEST_TMP/tracks"
  echo 'check_code "broken" (' >"$TEST_TMP/tracks/terraform/03-late/checks.sh"
  TRACKS_DIR="$TEST_TMP/tracks" run "$LAB" catchup --yes an-01
  [ "$status" -eq 1 ]
  [[ "$output" == *"not replaying terraform"* ]]
  [ -f "$(LIVE)/mine.txt" ]
  no_backup
}

@test "C2: catchup never commits files the learner's .gitignore ignored (terraform scope)" {
  printf '.env\nansible/.venv/\nansible/.facts/\n' >"$(LIVE)/.gitignore"
  git -C "$(LIVE)" add -A
  git -C "$(LIVE)" commit -q -m ignore
  git -C "$(LIVE)" push -q origin main
  echo 'GH_TOKEN=ghp_secret' >"$(LIVE)/.env"
  mkdir -p "$(LIVE)/ansible/.venv/bin" "$(LIVE)/ansible/.facts"
  echo py >"$(LIVE)/ansible/.venv/bin/python"
  echo facts >"$(LIVE)/ansible/.facts/vm-1"
  run "$LAB" catchup --yes tf-02
  echo "$output"
  [ "$status" -eq 0 ]
  pushed="$(git -C "$TEST_TMP/remote-live.git" ls-tree -r --name-only main)"
  echo "$pushed"
  [[ "$pushed" != *".env"* ]]
  [[ "$pushed" != *".venv"* ]]
  [[ "$pushed" != *".facts"* ]]
  [[ "$pushed" == *"terraform/main.tf"* ]]
  # still on disk, and still ignored though the reference replaced .gitignore
  [ "$(cat "$(LIVE)/.env")" = "GH_TOKEN=ghp_secret" ]
  [ -f "$(LIVE)/ansible/.venv/bin/python" ]
  [ -z "$(git -C "$(LIVE)" status --porcelain)" ]
}

@test "C2: ansible catchup never commits ansible/.venv the learner's ansible/.gitignore ignored" {
  mkdir -p "$(LIVE)/terraform" "$(LIVE)/ansible"
  echo mine >"$(LIVE)/terraform/late.tf"
  printf '.venv/\n' >"$(LIVE)/ansible/.gitignore"
  git -C "$(LIVE)" add -A
  git -C "$(LIVE)" commit -q -m work
  git -C "$(LIVE)" push -q origin main
  mkdir -p "$(LIVE)/ansible/.venv/bin"
  echo py >"$(LIVE)/ansible/.venv/bin/python"
  run "$LAB" catchup --yes an-02
  [ "$status" -eq 0 ]
  pushed="$(git -C "$TEST_TMP/remote-live.git" ls-tree -r --name-only main)"
  [[ "$pushed" != *".venv"* ]]
  [[ "$pushed" == *"ansible/roles.yml"* ]]
  [ -f "$(LIVE)/ansible/.venv/bin/python" ]
  [ -z "$(git -C "$(LIVE)" status --porcelain)" ]
}

@test "I1: terraform catchup keeps ansible/ and the Ansible workflows; cap-01 still replaces everything" {
  mkdir -p "$(LIVE)/ansible" "$(LIVE)/.github/workflows"
  echo learner >"$(LIVE)/ansible/own.yml"
  echo learner >"$(LIVE)/.github/workflows/ansible-ci.yml"
  echo learner >"$(LIVE)/.github/workflows/terraform.yml"
  git -C "$(LIVE)" add -A
  git -C "$(LIVE)" commit -q -m work
  git -C "$(LIVE)" push -q origin main
  run "$LAB" catchup --yes tf-25
  [ "$status" -eq 0 ]
  [ "$(cat "$(LIVE)/ansible/own.yml")" = learner ]
  [ "$(cat "$(LIVE)/.github/workflows/ansible-ci.yml")" = learner ]
  [ ! -e "$(LIVE)/.github/workflows/terraform.yml" ]
  [ ! -e "$(LIVE)/mine.txt" ]
  [ -f "$(LIVE)/terraform/late.tf" ]
  git -C "$TEST_TMP/remote-live.git" show main:ansible/own.yml
  run "$LAB" catchup --yes cap-01
  [ "$status" -eq 0 ]
  [ ! -e "$(LIVE)/ansible/own.yml" ]
  [ "$(cat "$(LIVE)/.github/workflows/ansible-ci.yml")" = "name: ansible-ci" ]
}

@test "I2: catchup and next refuse while the lab is paused" {
  : >"$LAB_HOME/paused"
  run "$LAB" catchup --yes tf-02
  [ "$status" -eq 7 ]
  [[ "$output" == *"lab is paused — ./lab.sh resume first"* ]]
  [ -f "$(LIVE)/mine.txt" ]
  no_backup
  run "$LAB" next terraform
  [ "$status" -eq 7 ]
  [[ "$output" == *"lab is paused — ./lab.sh resume first"* ]]
  [ ! -e "$LAB_HOME/progress" ]
}

@test "M1: catchup asks once for both repos, before replacing either" {
  run bash -c "printf 'y\nn\n' | '$LAB' catchup tf-25"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(grep -o '\[y/N\]' <<<"$output" | wc -l)" -eq 1 ]
  [[ "$output" == *"acme-platform and acme-terraform-modules"* ]]
  [ "$(cat "$TEST_TMP/acme/acme-terraform-modules/m.tf")" = "module acme" ]
  run bash -c "echo n | '$LAB' catchup tf-25"
  [ "$status" -eq 6 ]
  [[ "$output" == *"nothing replaced"* ]]
}
