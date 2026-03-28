#!/bin/bash
set -euo pipefail

APP_NAME="Modaliser"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
INSTALL_DIR="/Applications"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${SCRIPT_DIR}/build-app.sh"

echo "Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_NAME}.app"
echo "Installed ${INSTALL_DIR}/${APP_NAME}.app"
