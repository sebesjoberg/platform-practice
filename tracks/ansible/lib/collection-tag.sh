# shellcheck shell=bash
# Release tags of the collection acme.platform in the live repo, for catchup (the releases in
# collection-releases.txt, next to this file). From an-14 the Ansible code installs its own
# collection from git by tag:
#   - name: https://github.com/<owner>/<repo>.git#/ansible/collections_src/ansible_collections/acme/platform
#     type: git
#     version: acme.platform-X.Y.Z
# so the tag must exist on GitHub before ansible-galaxy can clone it. Sourced by ansible.sh
# (an_venv_sync, which every an-* catchup runs first) and by an-14/an-15's catchup.sh. Needs the
# config exported, LIVE_DIR a clone with an origin, and LAB_ROOT (exported by lab.sh; falls back
# to this file's location in the harness repo).

AN_COLLECTION_RELEASES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/collection-releases.txt"
# Where the collection's source lives in the live repo (the git URL's #/ fragment).
AN_COLLECTION_SRC=ansible/collections_src/ansible_collections/acme/platform

# an_collection_release_task <tag>: the task whose reference holds release <tag>; 1 if unknown.
an_collection_release_task() {
  awk -v t="$1" '!/^[[:space:]]*#/ && $1 == t { print $2; f = 1; exit } END { exit !f }' "$AN_COLLECTION_RELEASES"
}

# an_collection_tag <tag>: make <tag> on origin hold the collection source of the task that
# releases it (collection-releases.txt), whatever main holds now: catching up to an-20 puts the
# 1.1.0 source on main, but acme.platform-1.0.0 must stay the 1.0.0 collection. The tag points at
# origin/main when main's collection directory is exactly that release, else at a parentless
# commit holding only that directory (galaxy only reads the #/ subdirectory). A tag that already
# holds the release is left alone; one with other content (the learner's own) is moved after a
# warning, its old commit saved on origin as branch my-work/tag-<tag>-<time>. Idempotent.
an_collection_tag() {
  local tag=$1 id root tmp tree want have commit backup rref="refs/lab/remote-tags/$1"
  local -a gid=()
  id="$(an_collection_release_task "$tag")" || {
    echo "catchup: $tag is not a known collection release; add \"$tag <task id>\" to $AN_COLLECTION_RELEASES" >&2
    return 1
  }
  root="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  [[ -d "${LIVE_DIR:?}/.git" ]] || { echo "$id: $LIVE_DIR is not a git clone" >&2; return 1; }
  tmp="$(mktemp -d)"
  # shellcheck source=/dev/null
  if ! (source "$root/lib/common.sh" && source "$root/lib/tasks.sh" && source "$root/lib/template.sh" &&
    source "$root/lib/catchup.sh" && build_reference "$id" "$tmp/ref") >/dev/null ||
    [[ ! -f "$tmp/ref/live/$AN_COLLECTION_SRC/galaxy.yml" ]]; then
    echo "$id: could not build the collection of $id's reference" >&2
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "$tmp/tree/$AN_COLLECTION_SRC"
  cp -a "$tmp/ref/live/$AN_COLLECTION_SRC/." "$tmp/tree/$AN_COLLECTION_SRC/"
  tree="$(cd "$tmp/tree" && GIT_INDEX_FILE="$tmp/index" git --git-dir="$LIVE_DIR/.git" --work-tree=. add -A &&
    GIT_INDEX_FILE="$tmp/index" git --git-dir="$LIVE_DIR/.git" write-tree)"
  rm -rf "$tmp"
  want="$(git -C "$LIVE_DIR" rev-parse "$tree:$AN_COLLECTION_SRC")"
  if [[ -z "$(git -C "$LIVE_DIR" config user.email || true)" ]]; then
    gid=(-c user.name=platform-practice -c user.email=lab@localhost)
  fi

  git -C "$LIVE_DIR" fetch -q origin main
  git -C "$LIVE_DIR" update-ref -d "$rref" 2>/dev/null || true
  if [[ -n "$(git -C "$LIVE_DIR" ls-remote --tags origin "refs/tags/$tag")" ]]; then
    git -C "$LIVE_DIR" fetch -q origin "+refs/tags/$tag:$rref"
    have="$(git -C "$LIVE_DIR" rev-parse -q --verify "$rref^{commit}:$AN_COLLECTION_SRC" 2>/dev/null || true)"
    if [[ "$have" == "$want" ]]; then
      git -C "$LIVE_DIR" update-ref "refs/tags/$tag" "$rref"
      git -C "$LIVE_DIR" update-ref -d "$rref"
      echo "$id: $tag already holds the reference collection"
      return 0
    fi
    backup="my-work/tag-$tag-$(date +%Y%m%d-%H%M%S)"
    echo "WARNING: tag $tag in $(basename "$LIVE_DIR") is not the lab's reference release; catchup moves it and saves your version as branch $backup (on origin)." >&2
    git -C "$LIVE_DIR" push -q origin "$rref^{commit}:refs/heads/$backup"
    git -C "$LIVE_DIR" update-ref -d "$rref"
  fi

  if [[ "$(git -C "$LIVE_DIR" rev-parse -q --verify "refs/remotes/origin/main^{commit}:$AN_COLLECTION_SRC" 2>/dev/null || true)" == "$want" ]]; then
    commit="$(git -C "$LIVE_DIR" rev-parse refs/remotes/origin/main)"
  else
    commit="$(git -C "$LIVE_DIR" "${gid[@]}" commit-tree "$tree" -m "acme.platform $tag (catchup: reference of $id)")"
  fi
  git -C "$LIVE_DIR" "${gid[@]}" tag -f -a "$tag" -m "$tag (catchup: reference of $id)" "$commit" >/dev/null
  git -C "$LIVE_DIR" push -q -f origin "refs/tags/$tag"
  echo "$id: tagged $tag in $(basename "$LIVE_DIR") and pushed it"
}

# an_collection_pinned_tags: the tags ansible/collections/requirements.yml (in LIVE_DIR) pins for
# collections from the live repo itself, one per line.
an_collection_pinned_tags() {
  awk -v repo="github.com/${GH_OWNER:?}/${LIVE_REPO:?}" '
    /^[[:space:]]*-[[:space:]]/ { own = 0 }
    index($0, repo ".git#") || index($0, repo "#") { own = 1 }
    own && /^[[:space:]]*(-[[:space:]]*)?version:/ { v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v); print v; own = 0 }
  ' "$LIVE_DIR/ansible/collections/requirements.yml" 2>/dev/null
}

# an_collection_tag_pinned: tag every release of the live repo's collection that the tree pins.
an_collection_tag_pinned() {
  local t rc=0
  for t in $(an_collection_pinned_tags); do
    an_collection_tag "$t" || rc=1
  done
  return "$rc"
}
