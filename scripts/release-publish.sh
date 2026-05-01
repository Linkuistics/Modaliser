#!/usr/bin/env bash
#
# Publish the artifacts produced by release-build.sh:
#   1. Create a GitHub Release on Linkuistics/Modaliser for v<ver> and
#      upload the tarball from dist/.
#   2. Copy modaliser.rb into $MODALISER_TAP_DIR/Casks/, commit, push.
#
# Prerequisite: ./scripts/release-build.sh has just run successfully.
# Env: MODALISER_TAP_DIR (default ~/Development/homebrew-taps).

set -euo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST_DIR="$REPO_ROOT/dist"
readonly TAP_DIR="${MODALISER_TAP_DIR:-$HOME/Development/homebrew-taps}"

die() {
  echo "release-publish: $*" >&2
  exit 1
}

preflight() {
  command -v gh >/dev/null || die "gh CLI not on PATH"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated; run 'gh auth login'"
  [[ -d "$DIST_DIR" ]] || die "no $DIST_DIR; run scripts/release-build.sh first"
  [[ -f "$DIST_DIR/modaliser.rb" ]] || die "no rendered cask at $DIST_DIR/modaliser.rb"
  compgen -G "$DIST_DIR/*.tar.xz" >/dev/null || die "no tarballs in $DIST_DIR"
  [[ -d "$TAP_DIR/.git" ]] || die "tap clone not found at $TAP_DIR (set MODALISER_TAP_DIR)"
}

read_version() {
  git -C "$REPO_ROOT" describe --tags --abbrev=0 | sed 's/^v//'
}

verify_tag_matches_artifacts() {
  local version="$1"
  local sample
  sample="$(ls "$DIST_DIR"/modaliser-v*-aarch64-apple-darwin.tar.xz 2>/dev/null | head -n1)" \
    || die "missing aarch64-apple-darwin tarball"
  [[ "$sample" == *"modaliser-v${version}-"* ]] \
    || die "artifact version mismatch: $sample does not contain v${version}"
}

# Ensure the current branch and the v$version tag are present on origin
# before `gh release create` runs. Without this, gh creates a lightweight
# tag from origin's default-branch tip — which silently differs from the
# local annotated tag when there are unpushed commits, producing a release
# pointing at the wrong commit.
push_branch_and_tag() {
  local version="$1"
  local tag="v${version}"
  local remote_tag_sha local_tag_sha branch
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD)" \
    || die "HEAD is detached; release from a branch"

  echo "release-publish: pushing $branch to origin"
  git -C "$REPO_ROOT" push origin "$branch"

  local_tag_sha="$(git -C "$REPO_ROOT" rev-parse "$tag")"
  remote_tag_sha="$(git -C "$REPO_ROOT" ls-remote --tags origin "$tag" | awk '{print $1}')"
  if [[ -n "$remote_tag_sha" && "$remote_tag_sha" != "$local_tag_sha" ]]; then
    die "remote tag $tag ($remote_tag_sha) differs from local ($local_tag_sha); resolve manually"
  fi
  echo "release-publish: pushing tag $tag to origin"
  git -C "$REPO_ROOT" push origin "$tag"
}

create_github_release() {
  local version="$1"
  local tag="v${version}"
  echo "release-publish: creating GitHub Release $tag"
  gh release create "$tag" \
    --repo Linkuistics/Modaliser \
    --title "Release $tag" \
    --notes "Release $tag" \
    "$DIST_DIR"/*.tar.xz
}

push_cask_to_tap() {
  local version="$1"
  echo "release-publish: pushing cask to $TAP_DIR"
  mkdir -p "$TAP_DIR/Casks"
  cp "$DIST_DIR/modaliser.rb" "$TAP_DIR/Casks/modaliser.rb"
  git -C "$TAP_DIR" add Casks/modaliser.rb
  git -C "$TAP_DIR" commit -m "modaliser v${version}"
  git -C "$TAP_DIR" push
}

main() {
  preflight
  local version
  version="$(read_version)"
  verify_tag_matches_artifacts "$version"

  push_branch_and_tag "$version"
  create_github_release "$version"
  push_cask_to_tap "$version"

  echo
  echo "release-publish: done. Verify with:"
  echo "  brew update && brew install --cask linkuistics/taps/modaliser"
}

main "$@"
