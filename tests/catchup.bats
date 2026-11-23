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
  [ "${lines[0]}" = "tf-01 before-replace acme-platform" ]
  [ "${lines[1]}" = "tf-02 after-push acme-platform" ]
  [ "${lines[2]}" = "tf-25 after-push acme-platform" ]
  [ "${#lines[@]}" -eq 3 ]
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
}
