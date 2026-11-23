#!/usr/bin/env bash
# tf-11 catchup (after-push, cwd = LIVE_DIR): tf-04's hook already applied bootstrap (with the
# Resource Policy Contributor assignment) and tf-05's hook ran the pipeline (with the policy).
# A new policy assignment can take minutes, rarely 30, before Azure enforces it, so wait until an
# untagged rg-* group is refused. Same probe as the grader; the group never survives. Idempotent.
set -euo pipefail

probe="rg-$PREFIX-policytest"
for i in $(seq 1 40); do
  if [[ "$(az group exists -n "$probe")" == true ]]; then
    az group delete -n "$probe" --yes >/dev/null 2>&1 || true
  fi
  rc=0
  out="$(az group create -n "$probe" -l "$LOCATION" -o none 2>&1)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    az group delete -n "$probe" --yes >/dev/null 2>&1 || true
  elif grep -q RequestDisallowedByPolicy <<<"$out"; then
    echo "tf-11: the owner-tag policy is enforced"
    exit 0
  fi
  echo "tf-11: policy not enforced yet (attempt $i/40), retrying in 45s" >&2
  sleep 45
done
echo "tf-11: $PREFIX-require-owner-tag is still not enforced after 30 minutes; check az policy assignment list" >&2
exit 1
