# shellcheck shell=bash
# Release tags in the modules repo for catchup (tf-19 v1.0.0, tf-20 v2.0.0). Sourced by their
# catchup.sh and by tf-05's catchup.sh, which must create the tags the live tree pins before it
# runs the pipeline. Needs the config exported, MODULES_DIR a clone with an origin, TRACKS_DIR and
# LAB_ROOT (exported by lab.sh; falls back to this file's location in the harness repo).

# modules_tag <tag> <task-id>: make <tag> on origin point at the modules tree of <task-id>'s
# reference, whatever main holds now (catching up to tf-20 puts v2 on main, but v1.0.0 must stay
# the v1 module that env-prod pins). Uses main's commit when its tree is that tree, else a
# parentless commit with exactly that tree. A tag that already has the tree is left alone; one
# with other content (the learner's own release) is saved as branch my-work/tag-<tag>-<time>
# and moved, as catchup replaces main. Idempotent.
modules_tag() {
  local tag=$1 id=$2 root tmp tree have commit ts
  local -a gid=()
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

  git -C "$MODULES_DIR" fetch -q origin main
  if [[ -n "$(git -C "$MODULES_DIR" ls-remote --tags origin "refs/tags/$tag")" ]]; then
    git -C "$MODULES_DIR" fetch -q origin "+refs/tags/$tag:refs/tags/$tag"
    have="$(git -C "$MODULES_DIR" rev-parse "refs/tags/$tag^{tree}")"
    if [[ "$have" == "$tree" ]]; then
      echo "$id: $tag already holds the reference module"
      return 0
    fi
    ts="$(date +%Y%m%d-%H%M%S)"
    git -C "$MODULES_DIR" push -q origin "refs/tags/$tag^{commit}:refs/heads/my-work/tag-$tag-$ts"
    echo "$id: your $tag had other content; saved as branch my-work/tag-$tag-$ts, moving the tag"
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

# modules_tag_pinned: tag every release the live tree (cwd = LIVE_DIR) pins from the modules repo
# and that catchup knows how to build: v1.* -> tf-19's v1.0.0, v2.* -> tf-20's v2.0.0.
modules_tag_pinned() {
  local refs ref
  refs="$(grep -rhoE "git::https://github\.com/$GH_OWNER/$MODULES_REPO\.git//[^?\"]+\?ref=v[0-9]+" terraform --include='*.tf' |
    sed -E 's/.*ref=v//' | sort -un || true)"
  for ref in $refs; do
    case "$ref" in
      1) modules_tag v1.0.0 tf-19 ;;
      2) modules_tag v2.0.0 tf-20 ;;
      *) echo "catchup: no reference release for v$ref.x of $MODULES_REPO" >&2 ;;
    esac
  done
}
