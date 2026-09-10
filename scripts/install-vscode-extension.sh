#!/bin/bash
# Build the VSCode companion extension from a source checkout and install it
# (ADR-0026, ADR-0028).
#
# THIS IS THE DEVELOPER'S PATH, NOT THE USER'S. A released Modaliser ships the
# built extension inside `Modaliser.app` and copies it into
# `~/.vscode/extensions` on the user's confirmed request — a row on the VSCode
# screen, `(modaliser apps vscode)`'s `install-companion!` (ADR-0028). The
# release tarball is `Modaliser.app`, `README.md` and `LICENSE`, so a cask user
# has no `scripts/` directory and never runs this file. What this script is for
# is the loop the maintainer works in: edit `vscode-extension/src`, run this,
# restart VSCode — without a release build in between.
#
# ONLY THE BUILD IS HERE. The sweep-and-copy — the `rm -rf` inside another
# application's directory — lives in `scripts/install-companion-payload.sh`,
# which is also what the `.app` carries and runs. Two entry points, one
# deletion rule, and this one inherits the manifest check that keeps the sweep
# from eating a distinct sibling under the same prefix.
#
# Two standing caveats. `build-app.sh`'s exact-mirror invariant (ADR-0019)
# covers `Sources/Modaliser/Scheme/` only, so nothing fails a Modaliser build
# if this extension goes stale; and after installing from here, a later
# `install.sh` puts a possibly-different bundled version on disk while the copy
# under `~/.vscode/extensions` stays where this put it. The protocol version in
# the `parts` reply is what catches a skew either way — an empty panel with a
# log line, not wrong rows.
#
# The install is a directory copy into ~/.vscode/extensions rather than a
# `.vsix` through `code --install-extension`, because packaging a vsix needs
# @vscode/vsce and the copy is exactly what installing one does. That also
# keeps the repo free of a committed build artifact that nothing verifies —
# a point ADR-0028 reaffirms rather than spends: the bundled payload is
# produced during build-app.sh and never enters the repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../vscode-extension" && pwd)"

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm is required to build the extension" >&2
  exit 1
fi

echo "Building the companion extension..."
cd "${PROJECT_DIR}"
# Wipe first, for the reason build-app.sh wipes the bundle: tsc overwrites but
# does not prune, so a deleted source would otherwise leave its compiled output
# behind forever (ADR-0019's bug class).
rm -rf "${PROJECT_DIR}/out"
npm install --silent
npm run --silent build

"${SCRIPT_DIR}/install-companion-payload.sh" "${PROJECT_DIR}"

echo
echo "VSCode scans ~/.vscode/extensions at startup, so RESTART VSCODE (or run"
echo "'Developer: Reload Window' in each window) before Modaliser can reach it."
echo "Each window then listens on its own socket under"
echo "  ${HOME}/.config/modaliser/vscode/"
echo "and the window with focus names itself in that directory's 'focused'"
echo "file. 'Modaliser Companion' in the Output panel is the extension's log,"
echo "and is where a refused action says why — nothing comes back on the wire."
