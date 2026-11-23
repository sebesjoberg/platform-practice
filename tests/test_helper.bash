# Shared bats helper. Usage in a .bats file:
#   load test_helper
#   setup() { setup_lab; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/fakes/_encode
source "$REPO_ROOT/tests/fakes/_encode"
export REPO_ROOT

# setup_lab: isolated lab sandbox with fake az/gh/terraform first on PATH.
setup_lab() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export LAB_HOME="$TEST_TMP/lab-home"
  export FAKE_DIR="$TEST_TMP/fake"
  export FAKE_LOG="$TEST_TMP/fake.log"
  mkdir -p "$LAB_HOME" "$FAKE_DIR" "$TEST_TMP/acme/acme-platform" "$TEST_TMP/acme/acme-terraform-modules"
  : >"$FAKE_LOG"
  export PATH="$REPO_ROOT/tests/fakes:$PATH"

  cat >"$LAB_HOME/config.env" <<CFG
PREFIX=acme
SUFFIX=abc123
LOCATION=swedencentral
SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
TENANT_ID=11111111-1111-1111-1111-111111111111
GH_OWNER=learner
LIVE_REPO=acme-platform
MODULES_REPO=acme-terraform-modules
LIVE_DIR=$TEST_TMP/acme/acme-platform
MODULES_DIR=$TEST_TMP/acme/acme-terraform-modules
LEARNER_IP=203.0.113.10
OWNER_TAG=learner
CFG
}

teardown_lab() {
  [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# fake_response <tool> "<args>" <rc> [stdout]
# Registers a canned answer for `<tool> <args>`. Args are the argv joined by single spaces.
fake_response() {
  local tool=$1 args=$2 rc=$3 key
  key="$(fake_key "$args")"
  mkdir -p "$FAKE_DIR/$tool"
  printf '%s\n' "$rc" >"$FAKE_DIR/$tool/$key.rc"
  if [[ $# -ge 4 ]]; then
    printf '%s\n' "$4" >"$FAKE_DIR/$tool/$key.out"
  else
    : >"$FAKE_DIR/$tool/$key.out"
  fi
}
