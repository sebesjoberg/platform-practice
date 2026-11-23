#!/usr/bin/env bash
# tf-01 catchup (CATCHUP_PHASE=before-replace, only when LIVE_DIR is not yet a clone):
# create the public live repo if it is missing, clone it to LIVE_DIR and make sure main has a
# commit on origin (catchup needs a local main and origin/main to replace).
set -euo pipefail

repo="$GH_OWNER/$LIVE_REPO"

if [[ -d "$LIVE_DIR/.git" ]] && git -C "$LIVE_DIR" remote get-url origin >/dev/null 2>&1; then
  exit 0
fi

if ! gh repo view "$repo" >/dev/null 2>&1; then
  echo "tf-01: creating public repo $repo"
  gh repo create "$repo" --public --description "Acme platform (platform-practice lab)"
fi

mkdir -p "$LIVE_DIR"
if [[ ! -d "$LIVE_DIR/.git" ]]; then
  if [[ -n "$(ls -A "$LIVE_DIR")" ]]; then
    echo "tf-01: $LIVE_DIR is not empty and not a git repo; move it away and re-run" >&2
    exit 1
  fi
  gh repo clone "$repo" "$LIVE_DIR"
else
  url="$(gh repo view "$repo" --json url --jq .url).git"
  git -C "$LIVE_DIR" remote add origin "$url"
fi

cd "$LIVE_DIR"
gid=()
if [[ -z "$(git config user.email || true)" ]]; then
  gid=(-c user.name=platform-practice -c user.email=lab@localhost)
fi
if ! git rev-parse --verify -q HEAD >/dev/null; then
  if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
    git checkout -q -b main origin/main # remote has main but its HEAD points elsewhere
  else
    git symbolic-ref HEAD refs/heads/main
    git "${gid[@]}" commit -q --allow-empty -m "Initial commit"
  fi
fi
git rev-parse --verify -q refs/heads/main >/dev/null || {
  echo "tf-01: $LIVE_DIR has commits but no main branch; rename your default branch to main" >&2
  exit 1
}
git checkout -q main
git push -q -u origin main
