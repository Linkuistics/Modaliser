#!/bin/bash
# Install the VSCode companion extension from a source checkout (ADR-0026).
#
# THIS IS NO LONGER THE INTENDED INSTALL PATH FOR A RELEASED MODALISER, and
# the four reasons this header used to give for keeping it out of install.sh
# have been answered in ADR-0028. Read that before "restoring" the separation:
# the reasons were written for a reader holding this repository, and the
# release tarball is Modaliser.app + README.md + LICENSE, so a cask user has
# no scripts/ directory, no vscode-extension/, and no way to run this at all —
# while the shipped README.md tells them to. ADR-0028 decides instead that
# build-app.sh builds the extension into the bundle and Modaliser copies it
# into ~/.vscode/extensions on the user's confirmed request. When that lands,
# this script keeps only its BUILD step and delegates the sweep-and-copy below
# to the one shipped copy of that logic — two entry points, one `rm -rf` rule.
#
# Until then this is what runs, and its two standing caveats still hold.
# build-app.sh's exact-mirror invariant (ADR-0019) covers
# Sources/Modaliser/Scheme/ only, so nothing fails a Modaliser build if this
# extension goes stale; and reinstalling after a Modaliser upgrade is manual,
# with the protocol version in the `parts` reply the thing that catches you if
# you forget — a skew shows as an empty panel with a log line, not wrong rows.
#
# The install is a directory copy into ~/.vscode/extensions rather than a
# `.vsix` through `code --install-extension`, because packaging a vsix needs
# @vscode/vsce and the copy is exactly what installing one does. That also
# keeps the repo free of a committed build artifact that nothing verifies.
# ADR-0028 reaffirms that last point rather than spending it: the bundled
# payload is produced during build-app.sh and never enters the repository.
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
