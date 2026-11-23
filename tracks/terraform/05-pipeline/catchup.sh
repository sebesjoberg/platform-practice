#!/usr/bin/env bash
# tf-05 catchup (after-push, cwd = LIVE_DIR): set the repo variables, then dispatch the
# terraform workflow on main and wait for it (the push run may have started before the
# variables existed, and fresh role assignments can take minutes). From tf-24 the run's
# apply-prod job waits for the prod environment's reviewer; lib/ci-dispatch.sh approves it.
# Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$GH_OWNER/$LIVE_REPO"
wf=.github/workflows/terraform.yml
client_id="$(az identity show -g "rg-$PREFIX-tfstate" -n "id-$PREFIX-github-ci" --query clientId -o tsv)"
[[ -n "$client_id" ]] || { echo "tf-05: id-$PREFIX-github-ci not found (tf-04)" >&2; exit 1; }
gh variable set AZURE_CLIENT_ID -R "$repo" --body "$client_id"
gh variable set AZURE_TENANT_ID -R "$repo" --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID -R "$repo" --body "$SUBSCRIPTION_ID"

# The run below applies the tree catchup just pushed, which may be a later task's reference, and
# later tasks' hooks run after this one. So whatever the run needs from them happens here first;
# their own scripts are the single place that knows how.
# From tf-12 the workflow needs the repo variable BUDGET_EMAIL.
if grep -qs 'vars\.BUDGET_EMAIL' "$wf"; then
  bash "$here/../12-budget/catchup.sh"
fi
# From tf-25 it needs LEARNER_IP and SSH_PUBLIC_KEY (and the key pair they come from).
if grep -qsE 'vars\.(LEARNER_IP|SSH_PUBLIC_KEY)' "$wf"; then
  bash "$here/../25-vms-handover/catchup.sh"
fi
# From tf-19 the env stacks pull modules from the modules repo by tag, and the hooks of the
# tasks that release them (which create those tags) run after this one: create the tags first.
# shellcheck source=/dev/null
source "$here/../lib/modules-tag.sh"
modules_tag_pinned

# shellcheck source=/dev/null
source "$here/../lib/ci-dispatch.sh"
# shellcheck source=/dev/null
source "$here/../lib/acr-image.sh"
# From tf-23 env-dev runs hello:1.0 from the shared registry. Terraform doesn't push images, and
# the registry may be new (or recreated by a resume) and empty: build the shared stack first,
# import the image (tf-22's step), then run everything.
if acr_hello_needed "$PWD" && ! acr_hello_present; then
  ci_dispatch_wait "$repo" "landing-zone shared" tf-05
  acr_wait_ready 600
  acr_hello_import
fi
ci_dispatch_wait "$repo" all tf-05
