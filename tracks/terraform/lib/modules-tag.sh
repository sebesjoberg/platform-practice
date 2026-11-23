# shellcheck shell=bash
# Release tags in the modules repo for catchup (the releases in module-releases.txt, next to this
# file). Sourced by tf-19/tf-20's catchup.sh and by tf-05's catchup.sh, which must create the tags
# the live tree pins before it runs the pipeline. Needs the config exported, MODULES_DIR a clone
# with an origin, TRACKS_DIR and LAB_ROOT (exported by lab.sh; falls back to this file's location
# in the harness repo). CATCHUP_YES=1 (catchup --yes) moves tags without asking.

MODULES_RELEASES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/module-releases.txt"

# modules_release_task <tag>: prints the task whose reference holds release <tag>; 1 if unknown.
modules_release_task() {
  awk -v t="$1" '!/^[[:space:]]*#/ && $1 == t { print $2; f = 1; exit } END { exit !f }' "$MODULES_RELEASES"
}

# _modules_tag_confirm <tag> <whose> <backup>: warn that <tag> is about to move and where the
# learner's version will be saved. On an interactive terminal (or MODULES_TAG_PROMPT=1, a test
# hook) without CATCHUP_YES=1, ask. 0 = move it, 1 = keep the learner's tag.
_modules_tag_confirm() {
  local tag=$1 whose=$2 backup=$3 reply=""
  echo "WARNING: $whose tag $tag in $(basename "$MODULES_DIR") is not the lab's reference release; catchup moves it and saves your version as branch $backup." >&2
  if [[ "${CATCHUP_YES:-0}" != 1 ]] && { [[ -t 0 ]] || [[ "${MODULES_TAG_PROMPT:-}" == 1 ]]; }; then
    printf 'Move tag %s to the reference release? [y/N] ' "$tag" >&2
    read -r reply || true
    if [[ "$reply" != y && "$reply" != Y ]]; then
      echo "WARNING: kept your $tag. Stacks pinning it get your version, so later checks and plans may differ from the reference." >&2
      return 1
    fi
  fi
  return 0
}

# modules_tag <tag>: make <tag> on origin point at the modules tree of the task that releases it
# (module-releases.txt), whatever main holds now (catching up to tf-20 puts v2 on main, but v1.0.0
# must stay the v1 module that env-prod pins). Uses main's commit when its tree is that tree, else
# a parentless commit with exactly that tree. A tag that already has the tree is left alone.
# A tag with other content (the learner's own release, pushed or local only) is moved only after
# a warning (and, interactively, a yes), with the old commit saved as a my-work/tag-* branch.
# Idempotent.
modules_tag() {
  local tag=$1 id root tmp tree commit ts rref="refs/lab/remote-tags/$1" backup
  local -a gid=()
  id="$(modules_release_task "$tag")" || {
    echo "catchup: $tag is not a known module release; add \"$tag <task id>\" to $MODULES_RELEASES" >&2
    return 1
  }
  root="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  [[ -d "$MODULES_DIR/.git" ]] || { echo "$id: $MODULES_DIR is not a git clone" >&2; return 1; }
  tmp="$(mktemp -d)"
  # shellcheck source=/dev/null
  if ! (source "$root/lib/common.sh" && source "$root/lib/tasks.sh" && source "$root/lib/template.sh" &&
    source "$root/lib/catchup.sh" && build_reference "$id" "$tmp/ref") || [[ ! -d "$tmp/ref/modules" ]]; then
    echo "$id: could not build the reference modules tree of $id" >&2
    rm -rf "$tmp"
    return 1
  fi
  tree="$(cd "$tmp/ref/modules" && GIT_INDEX_FILE="$tmp/index" git --git-dir="$MODULES_DIR/.git" --work-tree=. add -A &&
    GIT_INDEX_FILE="$tmp/index" git --git-dir="$MODULES_DIR/.git" write-tree)"
  rm -rf "$tmp"
  if [[ -z "$(git -C "$MODULES_DIR" config user.email || true)" ]]; then
    gid=(-c user.name=platform-practice -c user.email=lab@localhost)
  fi
  ts="$(date +%Y%m%d-%H%M%S)"

  git -C "$MODULES_DIR" fetch -q origin main
  git -C "$MODULES_DIR" update-ref -d "$rref" 2>/dev/null || true
  if [[ -n "$(git -C "$MODULES_DIR" ls-remote --tags origin "refs/tags/$tag")" ]]; then
    git -C "$MODULES_DIR" fetch -q origin "+refs/tags/$tag:$rref"
  fi

  # A local tag with other content that origin doesn't have: save it locally before overwriting.
  if git -C "$MODULES_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null &&
    [[ "$(git -C "$MODULES_DIR" rev-parse "refs/tags/$tag^{tree}")" != "$tree" ]] &&
    { ! git -C "$MODULES_DIR" rev-parse -q --verify "$rref" >/dev/null ||
      [[ "$(git -C "$MODULES_DIR" rev-parse "refs/tags/$tag^{commit}")" != "$(git -C "$MODULES_DIR" rev-parse "$rref^{commit}")" ]]; }; then
    backup="my-work/tag-$tag-$ts-local"
    if ! _modules_tag_confirm "$tag" "your local (unpushed)" "$backup (local)"; then
      git -C "$MODULES_DIR" update-ref -d "$rref" 2>/dev/null || true
      return 0
    fi
    git -C "$MODULES_DIR" branch -f "$backup" "refs/tags/$tag^{commit}"
  fi

  if git -C "$MODULES_DIR" rev-parse -q --verify "$rref" >/dev/null; then
    if [[ "$(git -C "$MODULES_DIR" rev-parse "$rref^{tree}")" == "$tree" ]]; then
      git -C "$MODULES_DIR" update-ref "refs/tags/$tag" "$rref"
      git -C "$MODULES_DIR" update-ref -d "$rref"
      echo "$id: $tag already holds the reference module"
      return 0
    fi
    backup="my-work/tag-$tag-$ts"
    if ! _modules_tag_confirm "$tag" "your pushed" "$backup (on origin)"; then
      git -C "$MODULES_DIR" update-ref -d "$rref"
      return 0
    fi
    git -C "$MODULES_DIR" push -q origin "$rref^{commit}:refs/heads/$backup"
    git -C "$MODULES_DIR" update-ref -d "$rref"
  fi

  if [[ "$(git -C "$MODULES_DIR" rev-parse "refs/remotes/origin/main^{tree}")" == "$tree" ]]; then
    commit="$(git -C "$MODULES_DIR" rev-parse refs/remotes/origin/main)"
  else
    commit="$(git -C "$MODULES_DIR" "${gid[@]}" commit-tree "$tree" -m "spoke module $tag (catchup: reference of $id)")"
  fi
  git -C "$MODULES_DIR" "${gid[@]}" tag -f -a "$tag" -m "$tag (catchup: reference of $id)" "$commit" >/dev/null
  git -C "$MODULES_DIR" push -q -f origin "refs/tags/$tag"
  echo "$id: tagged $tag in $(basename "$MODULES_DIR") and pushed it"
}

# modules_tag_pinned: tag every release the live tree (cwd = LIVE_DIR) pins from the modules
# repo, by exact tag. A pinned tag missing from module-releases.txt fails loudly.
modules_tag_pinned() {
  local refs ref rc=0
  refs="$(grep --exclude-dir=.terraform -rhoE "git::https://github\.com/$GH_OWNER/$MODULES_REPO\.git//[^?\"]+\?ref=[^\"]+" terraform --include='*.tf' |
    sed -E 's/.*\?ref=//' | sort -u || true)"
  for ref in $refs; do
    modules_tag "$ref" || rc=1
  done
  return "$rc"
}
