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
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

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
