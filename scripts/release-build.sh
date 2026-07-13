#!/usr/bin/env bash
#
# Build a tarball containing the signed Modaliser.app for the current
# git tag and render a Homebrew Cask from
# scripts/templates/modaliser.rb.tmpl.
#
# Output: dist/
#   modaliser-v<ver>-aarch64-apple-darwin.tar.xz
#   modaliser.rb
#
# After this completes, inspect dist/ and run release-publish.sh.

set -euo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST_DIR="$REPO_ROOT/dist"
readonly TEMPLATE="$REPO_ROOT/scripts/templates/modaliser.rb.tmpl"
readonly TARGET="aarch64-apple-darwin"
readonly APP_NAME="Modaliser"

die() {
  echo "release-build: $*" >&2
  exit 1
}

require_clean_tagged_tree() {
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
    || die "working tree is dirty; commit or stash before releasing"
  git -C "$REPO_ROOT" describe --tags --exact-match HEAD >/dev/null 2>&1 \
    || die "HEAD is not a tagged commit; create one with 'git tag -a v<x.y.z> -m ...'"
}

read_version() {
  git -C "$REPO_ROOT" describe --tags --abbrev=0 | sed 's/^v//'
}

# build-app.sh copies the repo's Info.plist into the bundle verbatim, so the
# shipped version is whatever that file last hardcoded. Stamp it from the tag
# instead — the tag is the single source of truth for a release's version, and
# the two drifted apart for every release up to v2.7.0.
stamp_bundle_version() {
  local bundle="$1" version="$2"
  local plist="$bundle/Contents/Info.plist"
  echo "release-build: stamping bundle version $version" >&2
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist" >&2
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$plist" >&2
}

# build-app.sh signs with the local "Modaliser Dev" cert when present, which is
# meaningless on other machines. Re-sign ad-hoc so the release artifact has a
# consistent (if unverified) signature regardless of the builder's cert state.
# The version stamp must land before that re-sign: a signature seals Info.plist,
# so editing the plist afterwards would invalidate it.
build_app_bundle() {
  local version="$1"
  echo "release-build: building $APP_NAME.app" >&2
  bash "$REPO_ROOT/scripts/build-app.sh" >&2
  local built="$REPO_ROOT/.build/release/$APP_NAME.app"
  [[ -d "$built" ]] || die "build-app.sh did not produce $built"
  stamp_bundle_version "$built" "$version"
  echo "release-build: re-signing ad-hoc for distribution" >&2
  codesign --force --sign - "$built" >&2
  echo "$built"
}

assemble_bundle() {
  local built_app="$1"
  local stage="$DIST_DIR/staging"
  rm -rf "$stage"
  mkdir -p "$stage"

  cp -R "$built_app" "$stage/$APP_NAME.app"
  cp "$REPO_ROOT/README.md" "$stage/README.md"
  if [[ -f "$REPO_ROOT/LICENSE" ]]; then
    cp "$REPO_ROOT/LICENSE" "$stage/LICENSE"
  fi

  echo "$stage"
}

package_bundle() {
  local stage="$1" version="$2"
  local archive="$DIST_DIR/modaliser-v${version}-${TARGET}.tar.xz"
  echo "release-build: packaging $archive" >&2
  # Tar contents flat so the Cask's app stanza can reference Modaliser.app
  # at the staging-dir root rather than a versioned parent directory.
  local entries=("$APP_NAME.app" README.md)
  [[ -f "$stage/LICENSE" ]] && entries+=(LICENSE)
  tar -C "$stage" -cJf "$archive" "${entries[@]}"
  echo "$archive"
}

sha256_of() {
  shasum -a 256 "$1" | awk '{print $1}'
}

render_cask() {
  local version="$1" sha="$2"
  sed \
    -e "s|@VERSION@|${version}|g" \
    -e "s|@SHA_AARCH64_APPLE_DARWIN@|${sha}|g" \
    "$TEMPLATE" >"$DIST_DIR/modaliser.rb"
  echo "release-build: rendered $DIST_DIR/modaliser.rb"
}

main() {
  cd "$REPO_ROOT"
  "$REPO_ROOT/scripts/release-doctor.sh"
  require_clean_tagged_tree
  local version
  version="$(read_version)"
  echo "release-build: building modaliser v${version} for ${TARGET}"

  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR/staging"

  local built_app stage archive sha
  built_app="$(build_app_bundle "$version")"
  stage="$(assemble_bundle "$built_app")"
  archive="$(package_bundle "$stage" "$version")"
  sha="$(sha256_of "$archive")"
  render_cask "$version" "$sha"

  rm -rf "$DIST_DIR/staging"

  echo
  echo "release-build: artifacts in $DIST_DIR"
  ls -la "$DIST_DIR"
  echo
  echo "Inspect, then run scripts/release-publish.sh"
}

main "$@"
