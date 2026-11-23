#!/usr/bin/env bash
# tf-19 catchup.
#   CATCHUP_PHASE=before-replace (only when MODULES_DIR is not yet a clone): create the public
#     modules repo if it is missing, clone it to MODULES_DIR and make sure main has a commit on
#     origin (catchup needs a local main and origin/main to replace). Same pattern as tf-01.
#   CATCHUP_PHASE=after-push: tag v1.0.0 at tf-19's reference module and push it. tf-05's hook
#     does this earlier when the tree pins v1 (its pipeline run needs the tag), so here it is
#     normally a no-op.
# Idempotent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${CATCHUP_PHASE:-}" == after-push ]]; then
  # shellcheck source=/dev/null
  source "$here/../lib/modules-tag.sh"
  modules_tag v1.0.0 tf-19
  exit 0
fi

repo="$GH_OWNER/$MODULES_REPO"

if [[ -d "$MODULES_DIR/.git" ]] && git -C "$MODULES_DIR" remote get-url origin >/dev/null 2>&1; then
  exit 0
fi

if ! gh repo view "$repo" >/dev/null 2>&1; then
  echo "tf-19: creating public repo $repo"
  gh repo create "$repo" --public --description "Acme Terraform modules (platform-practice lab)"
fi

mkdir -p "$MODULES_DIR"
if [[ ! -d "$MODULES_DIR/.git" ]]; then
  if [[ -n "$(ls -A "$MODULES_DIR")" ]]; then
    echo "tf-19: $MODULES_DIR is not empty and not a git repo; move it away and re-run" >&2
    exit 1
  fi
  gh repo clone "$repo" "$MODULES_DIR"
else
  url="$(gh repo view "$repo" --json url --jq .url).git"
  git -C "$MODULES_DIR" remote add origin "$url"
fi
git -C "$MODULES_DIR" fetch -q origin

cd "$MODULES_DIR"
gid=()
if [[ -z "$(git config user.email || true)" ]]; then
  gid=(-c user.name=platform-practice -c user.email=lab@localhost)
fi
if ! git rev-parse --verify -q HEAD >/dev/null; then
  if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
    git checkout -q -b main origin/main # no commits of our own: start from origin/main
  else
    git symbolic-ref HEAD refs/heads/main
    git "${gid[@]}" commit -q --allow-empty -m "Initial commit"
  fi
fi
git rev-parse --verify -q refs/heads/main >/dev/null || {
  echo "tf-19: $MODULES_DIR has commits but no main branch; rename your default branch to main" >&2
  exit 1
}
git checkout -q main
if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
  if git merge-base --is-ancestor main origin/main; then
    git merge -q --ff-only origin/main # local main has nothing origin lacks: catch up
  elif ! git merge-base --is-ancestor origin/main main; then
    echo "tf-19: local main and origin/main in $MODULES_DIR have diverged; reconcile them first" >&2
    exit 1
  fi
fi
git push -q -u origin main
