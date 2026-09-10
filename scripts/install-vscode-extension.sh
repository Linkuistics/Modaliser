#!/bin/bash
# Install the VSCode companion extension (ADR-0026).
#
# Deliberately NOT a step inside install.sh: it targets a different
# application, requires that application to be present, and has its own
# upgrade cadence (docs/specs/vscode-window-parts.md, Out of scope). Note the
# corollary — build-app.sh's exact-mirror invariant (ADR-0019) covers
# Sources/Modaliser/Scheme/ only, so nothing fails a Modaliser build if this
# extension goes stale. Reinstalling after a Modaliser upgrade is manual, and
# the protocol version in the `parts` reply is what catches you if you forget:
# a skew shows as an empty panel with a log line, not as wrong rows.
#
# The install is a directory copy into ~/.vscode/extensions rather than a
# `.vsix` through `code --install-extension`, because packaging a vsix needs
# @vscode/vsce and the copy is exactly what installing one does. That also
# keeps the repo free of a committed build artifact that nothing verifies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../vscode-extension" && pwd)"
PUBLISHER="antony"
NAME="modaliser-companion"
EXTENSIONS_DIR="${HOME}/.vscode/extensions"

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm is required to build the extension" >&2
  exit 1
fi

VERSION="$(cd "${PROJECT_DIR}" && node -p "require('./package.json').version")"
TARGET="${EXTENSIONS_DIR}/${PUBLISHER}.${NAME}-${VERSION}"

echo "Building ${NAME} ${VERSION}..."
cd "${PROJECT_DIR}"
npm install --silent
npm run --silent build

echo "Installing to ${TARGET}..."
mkdir -p "${EXTENSIONS_DIR}"
# Any earlier version of THIS extension, and only this extension: VSCode would
# otherwise load two copies and each would bind its own socket in the same
# window.
find "${EXTENSIONS_DIR}" -maxdepth 1 -name "${PUBLISHER}.${NAME}-*" -exec rm -rf {} +
mkdir -p "${TARGET}/out"
cp "${PROJECT_DIR}/package.json" "${TARGET}/package.json"
cp "${PROJECT_DIR}/README.md" "${TARGET}/README.md"
# Only the extension's own compiled output — the tests compile into out/test
# and have no business in an installed extension.
cp -R "${PROJECT_DIR}/out/src" "${TARGET}/out/src"

echo
echo "Installed ${TARGET}"
echo
echo "VSCode scans ~/.vscode/extensions at startup, so RESTART VSCODE (or run"
echo "'Developer: Reload Window' in each window) before Modaliser can reach it."
echo "Each window then listens on its own socket under"
echo "  ${HOME}/.config/modaliser/vscode/"
echo "and the window with focus names itself in that directory's 'focused'"
echo "file. 'Modaliser Companion' in the Output panel is the extension's log,"
echo "and is where a refused action says why — nothing comes back on the wire."
