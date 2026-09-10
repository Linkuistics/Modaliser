#!/bin/bash
# Regression tests for scripts/install-companion-payload.sh — the one `rm -rf`
# Modaliser runs inside another application's directory (ADR-0028).
#
# WHY THIS IS A SCRIPT AND NOT A @Test. The Swift suite reaches nothing outside
# its own process — no network, no live terminals, no spawning at all — and
# that is structural rather than per-test discipline (ADR-0023). A test that
# executed this script would be the first exception to it, and the value of the
# property is that it has none. So the destructive cases live here, beside
# check-portable-surface.sh and check-decision-free.sh, in the same
# nothing-runs-it-for-you local discipline the repository already has.
#
# EVERY CASE RUNS AGAINST AN ISOLATED TEMPORARY EXTENSIONS DIRECTORY. Nothing
# here reads or writes ~/.vscode; the script takes the extensions directory as
# its second argument precisely so this is possible, and the fixture root is
# made with mktemp -d and removed on exit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="${SCRIPT_DIR}/install-companion-payload.sh"
MARKER=".modaliser-installed"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/modaliser-companion-tests.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

failures=0
cases=0
current=""
CASE=""

# A fresh fixture directory per case, so one case cannot see another's state.
start() {
  current="$1"
  cases=$((cases + 1))
  CASE="${ROOT}/case-${cases}"
  mkdir -p "$CASE"
  printf '%s\n' "- ${current}"
}

ok() { printf '  ok   %s\n' "$1"; }
bad() {
  printf '  FAIL %s: %s\n' "$current" "$1" >&2
  failures=$((failures + 1))
}

# Assertions as statements, deliberately not `test … || bad …`: this file runs
# under `set -e`, where a failing left-hand side of an AND/OR list is exactly
# the shape that ends the run early and reports nothing.
expect_exists() {
  if [[ ! -e "$1" ]]; then bad "$2"; fi
}
expect_absent() {
  if [[ -e "$1" ]]; then bad "$2"; fi
}
# Runs the installer, expecting it to REFUSE. Output is kept and shown only on
# an unexpected success, so a passing run stays quiet.
expect_refusal() {
  local out
  if out="$("$INSTALL" "$@" 2>&1)"; then
    bad "exited zero when it should have refused: ${out}"
  else
    ok "refused"
  fi
}
expect_install() {
  if ! "$INSTALL" "$@" >/dev/null; then bad "a valid install failed"; fi
}

# An extension directory (installed copy or payload) with a well-formed
# manifest and the three things the copy needs.
make_extension() {
  local dir="$1" publisher="$2" name="$3" version="$4"
  mkdir -p "${dir}/out/src"
  printf '{"publisher":"%s","name":"%s","version":"%s","main":"./out/src/extension.js"}\n' \
    "$publisher" "$name" "$version" > "${dir}/package.json"
  printf 'readme for %s\n' "$version" > "${dir}/README.md"
  printf 'exports.activate=function(){};\n' > "${dir}/out/src/extension.js"
}

# ── 1. A manifest that traverses is refused, and refused before anything is
#       removed. The destination is CONSTRUCTED from these fields and wiped
#       with rm -rf, so this is the check that bounds the wipe.
start "traversing publisher is refused with nothing removed"
mkdir -p "${CASE}/scope/extensions"
echo sentinel > "${CASE}/scope/keep-me"
make_extension "${CASE}/payload" "../../victim" "modaliser-companion" "1.0.0"
make_extension "${CASE}/scope/extensions/antony.modaliser-companion-0.9.0" \
  antony modaliser-companion 0.9.0
expect_refusal "${CASE}/payload" "${CASE}/scope/extensions"
expect_exists "${CASE}/scope/keep-me" "removed a file outside the extensions directory"
expect_absent "${CASE}/victim.modaliser-companion-1.0.0" \
  "installed outside the extensions directory"
expect_exists "${CASE}/scope/extensions/antony.modaliser-companion-0.9.0" \
  "removed the installed copy before refusing"
ok "nothing outside the extensions directory was touched"

start "a traversing publisher is refused by --print-identity too"
make_extension "${CASE}/payload" "antony" "../escape" "1.0.0"
expect_refusal --print-identity "${CASE}/payload"

# ── 2. An incomplete payload must not destroy the working copy that is
#       already installed. Everything after the preflight is destructive
#       first and constructive second.
start "an incomplete payload leaves the installed copy alone"
mkdir -p "${CASE}/extensions"
make_extension "${CASE}/extensions/antony.modaliser-companion-0.9.0" \
  antony modaliser-companion 0.9.0
date -u +%Y-%m-%dT%H:%M:%SZ > "${CASE}/extensions/antony.modaliser-companion-0.9.0/${MARKER}"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
rm "${CASE}/payload/README.md"
expect_refusal "${CASE}/payload" "${CASE}/extensions"
expect_exists "${CASE}/extensions/antony.modaliser-companion-0.9.0/${MARKER}" \
  "destroyed the working 0.9.0 installation"
expect_absent "${CASE}/extensions/antony.modaliser-companion-1.0.0" \
  "left a partial 1.0.0 directory behind"
ok "the working installation survived and no partial copy was created"

start "a payload missing out/src is refused"
mkdir -p "${CASE}/extensions"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
rm -rf "${CASE}/payload/out"
expect_refusal "${CASE}/payload" "${CASE}/extensions"

# ── 3. The happy path, and what the sweep must and must not remove.
start "installs, sweeps older copies, spares a distinct sibling"
mkdir -p "${CASE}/extensions"
make_extension "${CASE}/extensions/antony.modaliser-companion-0.9.0" \
  antony modaliser-companion 0.9.0
make_extension "${CASE}/extensions/antony.modaliser-companion-beta-1.0.0" \
  antony modaliser-companion-beta 1.0.0
mkdir -p "${CASE}/extensions/some.other-extension-2.0.0"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
expect_install "${CASE}/payload" "${CASE}/extensions"
target="${CASE}/extensions/antony.modaliser-companion-1.0.0"
expect_exists "${target}/${MARKER}" \
  "no completion marker — the row would offer a reinstall forever"
expect_exists "${target}/package.json" "no manifest in the installed copy"
expect_exists "${target}/README.md" "no README in the installed copy"
expect_exists "${target}/out/src/extension.js" "no compiled output in the installed copy"
expect_absent "${CASE}/extensions/antony.modaliser-companion-0.9.0" \
  "left the older copy — VSCode would load two and each would bind a socket"
expect_exists "${CASE}/extensions/antony.modaliser-companion-beta-1.0.0/package.json" \
  "swept a DISTINCT extension that merely matched the glob"
expect_exists "${CASE}/extensions/some.other-extension-2.0.0" "removed an unrelated extension"
ok "installed, swept the older copy, spared the sibling and the unrelated one"

start "a symlinked older copy is swept, and its target is not followed"
mkdir -p "${CASE}/extensions" "${CASE}/elsewhere"
make_extension "${CASE}/elsewhere/dev-checkout" antony modaliser-companion 0.9.0
ln -s "${CASE}/elsewhere/dev-checkout" "${CASE}/extensions/antony.modaliser-companion-0.9.0"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
expect_install "${CASE}/payload" "${CASE}/extensions"
expect_absent "${CASE}/extensions/antony.modaliser-companion-0.9.0" \
  "left the symlinked older copy"
expect_exists "${CASE}/elsewhere/dev-checkout/package.json" \
  "followed the symlink and destroyed the developer's checkout"
ok "the link went, the checkout stayed"

start "the destination is wiped, not merged"
mkdir -p "${CASE}/extensions"
make_extension "${CASE}/extensions/antony.modaliser-companion-1.0.0" \
  antony modaliser-companion 1.0.0
echo stale > "${CASE}/extensions/antony.modaliser-companion-1.0.0/out/src/retired.js"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
expect_install "${CASE}/payload" "${CASE}/extensions"
expect_absent "${CASE}/extensions/antony.modaliser-companion-1.0.0/out/src/retired.js" \
  "merged — a file deleted from the payload lingers forever"
expect_absent "${CASE}/extensions/antony.modaliser-companion-1.0.0/out/src/src" \
  "copied out/src one level down; the manifest's main would miss"
ok "wiped before copying"

start "installing a payload onto itself is refused"
mkdir -p "${CASE}/extensions"
make_extension "${CASE}/extensions/antony.modaliser-companion-1.0.0" \
  antony modaliser-companion 1.0.0
expect_refusal "${CASE}/extensions/antony.modaliser-companion-1.0.0" "${CASE}/extensions"
expect_exists "${CASE}/extensions/antony.modaliser-companion-1.0.0/package.json" \
  "destroyed the payload it was pointed at"
ok "the installed copy survived"

# ── 4. The status record the Scheme predicate reads. The wrapper is
#       `(modaliser apps vscode)`'s `companion-install-command`; what matters
#       here is that the script's own chatter never occupies the LAST line.
start "the wrapper's status record is always the final line"
mkdir -p "${CASE}/extensions/antony.modaliser-companion-modaliser-install-status=0"
make_extension "${CASE}/payload" antony modaliser-companion 1.0.0
transcript="$("$INSTALL" "${CASE}/payload" "${CASE}/extensions" 2>&1; echo "modaliser-install-status=$?")"
last="$(printf '%s\n' "$transcript" | tail -n 1)"
if [[ "$last" != "modaliser-install-status=0" ]]; then
  bad "final line was '${last}', not the wrapper's status record"
fi
# And the chatter above it really can carry the token — the sweep prints that
# candidate by name — which is the whole reason `companion-install-succeeded?`
# compares the last line instead of searching the transcript.
if ! printf '%s\n' "$transcript" | sed '$d' | grep -q 'modaliser-install-status=0'; then
  bad "the fixture no longer puts the token in the chatter; the spoof case is not being exercised"
fi
ok "the status record is last, above chatter that carries the token"

if [[ $failures -eq 0 ]]; then
  echo "install-companion-payload.sh: all cases pass"
else
  echo "install-companion-payload.sh: ${failures} failure(s)" >&2
  exit 1
fi
