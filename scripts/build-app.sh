#!/bin/bash
set -euo pipefail

APP_NAME="Modaliser"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Preconditions first, before anything is destroyed. npm builds the VSCode
# companion payload below (ADR-0028); checking for it after the wipe would
# abort partway and leave .build/release/Modaliser.app half-assembled,
# unsigned and iconless — a directory that looks like a build product.
# release-doctor.sh checks the same thing earlier, for the same reason.
if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm is required to build the VSCode companion extension" >&2
    echo "       (ADR-0028; brew install node)" >&2
    exit 1
fi

echo "Building ${APP_NAME}..."
swift build -c release

echo "Creating ${APP_NAME}.app..."
# Wipe first: the bundle must be a pure function of the source tree. `cp -R`
# into an existing directory MERGES — fresh files overwrite, deleted ones
# linger forever — so without this the .app (and via SysSync the user's
# sys/ mirror, ADR-0019) keeps shipping libraries retired months ago.
# Everything below already rebuilds unconditionally (icon, LispKit libraries,
# signature), so the wipe costs only the resource re-copy. APP_BUNDLE is a
# quoted, repo-relative path built from literals under `set -u`.
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Copy SPM resource bundle (contains Scheme files)
RESOURCE_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
    echo "Copied resource bundle"
fi

# Invariant: the bundled Scheme tree is a faithful image of the source tree —
# same membership, same content. SysSync mirrors this tree verbatim into
# ~/.config/modaliser/sys/scheme/, so anything stale here goes stale in every
# install (ADR-0019). Fails the build rather than shipping drift; catches both
# a regression to merge-copy semantics and SPM silently dropping a resource.
SOURCE_SCHEME="Sources/${APP_NAME}/Scheme"
BUNDLED_SCHEME="${APP_BUNDLE}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle/Scheme"
if ! SCHEME_DRIFT="$(diff -rq "$SOURCE_SCHEME" "$BUNDLED_SCHEME" 2>&1)"; then
    echo "Error: bundled Scheme tree is not a faithful image of ${SOURCE_SCHEME}:" >&2
    echo "$SCHEME_DRIFT" >&2
    exit 1
fi
echo "Verified bundled Scheme tree matches ${SOURCE_SCHEME}"

# ─── The VSCode companion payload (ADR-0028) ─────────────────────────────
#
# The extension that answers what is open inside a VSCode window ships INSIDE
# the app, because the release tarball is Modaliser.app + README.md + LICENSE
# and a cask user therefore has no scripts/ directory to install it from.
# Modaliser copies it into ~/.vscode/extensions only on the user's confirmed
# request — nothing here writes outside the bundle.
#
# Deliberately NOT under the diff -rq invariant above and not to be described
# as if it were: the copy source is produced by the step immediately before it,
# so there is no drift for a comparison to catch. What DOES have to be explicit
# is the wipe — tsc overwrites but does not prune, so a source deleted from
# vscode-extension/src would otherwise leave its compiled output in the payload
# forever. Same wipe-before-assemble rule, same bug class, as ADR-0019's.
#
# Three siblings land in Contents/Resources, and all three are derived from the
# ONE parameter (modaliser apps vscode) receives at boot, by suffix:
#   ModaliserCompanion/            the payload
#   ModaliserCompanion.id          '<publisher>.<name>-<version>' — the portable
#                                  tree has no directory listing (ADR-0027), so
#                                  the identity must sit at a fixed path
#   ModaliserCompanion.install.sh  the one sweep-and-copy rule, shipped
EXTENSION_DIR="vscode-extension"
COMPANION_DST="${APP_BUNDLE}/Contents/Resources/ModaliserCompanion"

echo "Building the VSCode companion extension..."
rm -rf "${EXTENSION_DIR}/out"
# npm ci, not npm install: this is a release build, so it resolves from the
# committed lockfile and cannot rewrite it as a side effect.
(cd "${EXTENSION_DIR}" && npm ci --silent && npm run --silent build)

mkdir -p "${COMPANION_DST}/out"
cp "${EXTENSION_DIR}/package.json" "${COMPANION_DST}/package.json"
cp "${EXTENSION_DIR}/README.md" "${COMPANION_DST}/README.md"
# Only the extension's own compiled output — the tests compile into out/test
# and have no business in an installed extension.
cp -R "${EXTENSION_DIR}/out/src" "${COMPANION_DST}/out/src"

cp scripts/install-companion-payload.sh "${COMPANION_DST}.install.sh"
chmod +x "${COMPANION_DST}.install.sh"
scripts/install-companion-payload.sh --print-identity "${COMPANION_DST}" \
    > "${COMPANION_DST}.id"
echo "Bundled companion extension $(cat "${COMPANION_DST}.id")"

# Copy LispKit's bundled R7RS+SRFI Libraries. LispKit's Package.swift
# excludes its Resources/ directory from SPM bundling (it's designed to
# be loaded via a -r CLI flag in REPL contexts) so we must vendor it
# explicitly into our .app bundle. SchemeEngine adds this path to the
# library search path at startup.
LISPKIT_LIBS_SRC=".build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries"
LISPKIT_LIBS_DST="${APP_BUNDLE}/Contents/Resources/LispKitLibraries"
if [ -d "$LISPKIT_LIBS_SRC" ]; then
    rm -rf "$LISPKIT_LIBS_DST"
    # ditto --noextattr strips the per-file xattrs SPM checkouts carry;
    # otherwise the later xattr -cr fails on read-only attrs we don't own.
    /usr/bin/ditto --noextattr --noqtn "$LISPKIT_LIBS_SRC" "$LISPKIT_LIBS_DST"
    echo "Copied LispKit standard libraries"
else
    echo "Warning: LispKit Libraries source not found at $LISPKIT_LIBS_SRC"
fi

# Generate .icns from source PNG
ICON_SOURCE="Resources/AppIcon.png"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
ICNS_FILE="${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

if [ -f "$ICON_SOURCE" ]; then
    echo "Generating AppIcon.icns..."
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    declare -a SIZES=(16 32 128 256 512)
    for size in "${SIZES[@]}"; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "${ICONSET_DIR}/icon_${size}x${size}.png" > /dev/null
        retina=$((size * 2))
        sips -z "$retina" "$retina" "$ICON_SOURCE" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" > /dev/null
    done

    iconutil --convert icns --output "$ICNS_FILE" "$ICONSET_DIR"
    rm -rf "$ICONSET_DIR"
    echo "Generated ${ICNS_FILE}"
else
    echo "Warning: ${ICON_SOURCE} not found, skipping icon generation."
fi

# Clear quarantine/provenance attributes that prevent launch. Some files
# from SPM checkouts carry xattrs we can't clear (read-only); ignore those.
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo "Signing ${APP_NAME}.app..."
# Use "Modaliser Dev" certificate for stable identity across rebuilds.
# This preserves Accessibility TCC permissions between builds.
# Falls back to ad-hoc signing if the certificate isn't found. That branch
# also fires when the cert exists but lost its explicit trust setting —
# find-identity -v hides untrusted identities, and a macOS update can wipe
# the trust store (observed after 26.5.2, 2026-07). Re-trust with:
#   security add-trusted-cert -p codeSign \
#     -k ~/Library/Keychains/login.keychain-db <exported-cert.pem>
if security find-identity -v -p codesigning | grep -q "Modaliser Dev"; then
    codesign --force --sign "Modaliser Dev" "${APP_BUNDLE}"
else
    echo "Warning: 'Modaliser Dev' certificate not found, using ad-hoc signing."
    echo "Accessibility permissions will need to be re-granted after each rebuild."
    codesign --force --sign - "${APP_BUNDLE}"
fi

echo "Built ${APP_BUNDLE}"
