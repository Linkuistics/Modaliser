#!/bin/bash
set -euo pipefail

APP_NAME="Modaliser"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Building ${APP_NAME}..."
swift build -c release

echo "Creating ${APP_NAME}.app..."
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
