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

echo "Signing ${APP_NAME}.app..."
# Use "Modaliser Dev" certificate for stable identity across rebuilds.
# This preserves Accessibility TCC permissions between builds.
# Falls back to ad-hoc signing if the certificate isn't found.
if security find-identity -v -p codesigning | grep -q "Modaliser Dev"; then
    codesign --force --sign "Modaliser Dev" "${APP_BUNDLE}"
else
    echo "Warning: 'Modaliser Dev' certificate not found, using ad-hoc signing."
    echo "Accessibility permissions will need to be re-granted after each rebuild."
    codesign --force --sign - "${APP_BUNDLE}"
fi

echo "Built ${APP_BUNDLE}"
