#!/bin/bash
# Sweep-and-copy an ALREADY-BUILT companion-extension payload into
# ~/.vscode/extensions (ADR-0028).
#
# This is the one and only transcription of the deletion rule. It has two
# entry points and no third: `scripts/install-vscode-extension.sh` builds from
# a source checkout and then delegates here, and the shipped `.app` carries a
# copy of this file beside its payload and runs it from
# `(modaliser apps vscode)`'s `install-companion!` op. The reason for the
# single copy is the `rm -rf` below: it runs inside ANOTHER application's
# directory, and two transcriptions of that is one too many.
#
# THE GLOB PROPOSES, THE MANIFEST CONFIRMS. VSCode names an installed
# extension's directory `<publisher>.<name>-<version>`, and an extension name
# may contain hyphens — this one's is `modaliser-companion` — so
# `antony.modaliser-companion-*` marks no boundary between name and version
# and matches a DISTINCT sibling such as `antony.modaliser-companion-beta-1.0.0`
# just as readily as an older copy of this extension. The glob is therefore a
# candidate filter only: each candidate is confirmed by reading its own
# package.json and requiring `publisher` and `name` to equal this payload's
# exactly. A directory that does not parse, or that names something else, is
# left alone.
#
# Sweeping at all is not tidiness — VSCode would load two copies of this
# extension in one window and each would bind its own socket.
#
# `~/.vscode/extensions/extensions.json` — the metadata cache recent VSCode
# keeps beside these directories — is deliberately not touched, exactly as the
# repository installer has never touched it: directory-scan installation is
# still supported and this is what has been in service. If a swept directory
# ever leaves a stale entry that VSCode complains about, that is the place to
# look first.
#
# plutil, not node and not python3, does the JSON reads: it is part of the base
# system, so this works on a cask user's machine that has never seen a
# toolchain. A malformed manifest makes it exit non-zero, which reads here as
# "not ours".
set -euo pipefail

PROGRAM="$(basename "$0")"

# Written into the installed directory as the LAST step, and the file
# (modaliser apps vscode)'s `companion-installed?` tests for. See the write
# site for why it is not a plain directory test.
MARKER=".modaliser-installed"

usage() {
  cat >&2 <<EOF
usage: ${PROGRAM} <payload-dir> [extensions-dir]
       ${PROGRAM} --print-identity <payload-dir>

  payload-dir      a built extension: package.json, README.md, out/src
  extensions-dir   defaults to \$HOME/.vscode/extensions

--print-identity writes '<publisher>.<name>-<version>' and exits. build-app.sh
uses it to stamp the identity file the Scheme op reads, so the identity has one
derivation rather than two.
EOF
  exit 2
}

# A top-level string field of a JSON file, or empty on any failure.
json_field() {
  /usr/bin/plutil -extract "$2" raw -o - -- "$1" 2>/dev/null || true
}

payload_identity() {
  local dir="$1" manifest publisher name version
  manifest="${dir}/package.json"
  [[ -f "$manifest" ]] || { echo "error: no package.json in ${dir}" >&2; exit 1; }
  publisher="$(json_field "$manifest" publisher)"
  name="$(json_field "$manifest" name)"
  version="$(json_field "$manifest" version)"
  if [[ -z "$publisher" || -z "$name" || -z "$version" ]]; then
    echo "error: ${manifest} does not name a publisher, name and version" >&2
    exit 1
  fi
  printf '%s.%s-%s\n' "$publisher" "$name" "$version"
}

main() {
  if [[ "${1:-}" == "--print-identity" ]]; then
    [[ $# -eq 2 ]] || usage
    payload_identity "$2"
    return
  fi

  [[ $# -ge 1 && $# -le 2 ]] || usage

  local payload extensions manifest publisher name version target
  payload="$1"
  if [[ -n "${2:-}" ]]; then
    extensions="$2"
  else
    extensions="${HOME:?HOME is unset; cannot locate ~/.vscode/extensions}/.vscode/extensions"
  fi
  [[ -d "$payload" ]] || { echo "error: no payload at ${payload}" >&2; exit 1; }
  payload="$(cd "$payload" && pwd -P)"

  manifest="${payload}/package.json"
  publisher="$(json_field "$manifest" publisher)"
  name="$(json_field "$manifest" name)"
  version="$(json_field "$manifest" version)"
  if [[ -z "$publisher" || -z "$name" || -z "$version" ]]; then
    echo "error: ${manifest} does not name a publisher, name and version" >&2
    exit 1
  fi
  target="${extensions}/${publisher}.${name}-${version}"

  # Installing a payload onto itself. Refuse it HERE, before anything is
  # removed: the destination is wiped before the copy, and when the
  # destination *is* the payload that wipe destroys the source — leaving the
  # user with no extension at all and a failed copy. The sweep's own
  # payload-exclusion below cannot save this case, because the wipe is not the
  # sweep. Reachable the moment someone points this at an installed copy to
  # refresh it, which is a reasonable thing to try.
  if [[ -d "$target" && "$(cd "$target" && pwd -P)" == "$payload" ]]; then
    echo "error: ${payload} is already the installed copy — nothing to do" >&2
    exit 1
  fi

  mkdir -p "$extensions"

  # Sweep. Every candidate is confirmed against its own manifest before it is
  # removed; `find -print0` rather than `-exec rm -rf` because the decision is
  # per-directory now, not per-match.
  #
  # `-type l` as well as `-type d`: symlinking an extension into
  # ~/.vscode/extensions is VSCode's own local-development idiom, and a
  # symlinked older copy that the sweep skipped would be loaded alongside the
  # new one — each binding its own socket in the same window, which is the
  # exact outcome sweeping exists to prevent. `rm -rf` on a symlink removes the
  # link and not its target, so confirming through the link and deleting it is
  # safe.
  #
  # And never the payload itself. The payload matches its own glob and passes
  # its own manifest check, so "the manifest confirms" cannot save us here —
  # this is the one candidate that has to be excluded by identity of PATH.
  # Reachable whenever someone points this at an installed copy to refresh it.
  local candidate cand_publisher cand_name resolved
  while IFS= read -r -d '' candidate; do
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P || echo "")"
    if [[ -n "$resolved" && "$resolved" == "$payload" ]]; then
      echo "Leaving ${candidate} (it is the payload being installed)"
      continue
    fi
    cand_publisher="$(json_field "${candidate}/package.json" publisher)"
    cand_name="$(json_field "${candidate}/package.json" name)"
    if [[ "$cand_publisher" == "$publisher" && "$cand_name" == "$name" ]]; then
      echo "Removing ${candidate}"
      rm -rf "$candidate"
    else
      echo "Leaving ${candidate} (its package.json names ${cand_publisher:-?}.${cand_name:-?})"
    fi
  done < <(find "$extensions" -maxdepth 1 \( -type d -o -type l \) -name "${publisher}.${name}-*" -print0)

  # Wipe the destination before copying. `cp -R` into an EXISTING directory
  # merges — a file deleted from the payload lingers forever, and
  # `cp -R src target/out/src` with target/out/src already present copies the
  # tree one level DOWN, so package.json's `main` would resolve to whatever
  # stale code was there. Same rule, same bug class, as build-app.sh's wipe
  # (ADR-0019). The sweep above cannot be relied on for this: it deliberately
  # LEAVES a directory whose manifest does not parse, and that is precisely the
  # directory a merge would corrupt.
  rm -rf "$target"

  # Copy. Only the extension's own compiled output — the tests compile into
  # out/test and have no business in an installed extension.
  mkdir -p "${target}/out"
  cp "${payload}/package.json" "${target}/package.json"
  cp "${payload}/README.md" "${target}/README.md"
  cp -R "${payload}/out/src" "${target}/out/src"

  # LAST, and only on success: the marker `companion-installed?` tests for.
  # A directory test alone would read a half-finished copy — a full disk, an
  # I/O error after mkdir — as *installed*, and the row that gates on it would
  # retire itself with no way back to a reinstall. Writing this last is what
  # makes "installed" mean "the copy completed" rather than "something is
  # there". A copy installed by hand, or by an older Modaliser, carries no
  # marker and so reads as not-installed: the row offers a reinstall, which is
  # harmless and is the right offer.
  date -u +%Y-%m-%dT%H:%M:%SZ > "${target}/${MARKER}"

  echo "Installed ${target}"
}

main "$@"
