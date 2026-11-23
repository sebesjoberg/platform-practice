#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  setup_lab
}

@test "fake az returns canned output" {
  fake_response az "account show" 0 '{"id":"fake"}'
  run az account show
  [ "$status" -eq 0 ]
  [ "$output" = '{"id":"fake"}' ]
  grep -qx 'az account show' "$FAKE_LOG"
}

@test "fake without response fails" {
  run --separate-stderr az group list
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"fake: no response for az group list"* ]]
}

@test "fixture config.env is sourceable" {
  # shellcheck disable=SC1091
  source "$LAB_HOME/config.env"
  [ "$PREFIX" = acme ]
  [ "$SUFFIX" = abc123 ]
  [ "$GH_OWNER" = learner ]
  [ -d "$LIVE_DIR" ]
  [ -d "$MODULES_DIR" ]
}

teardown() {
  teardown_lab
}
