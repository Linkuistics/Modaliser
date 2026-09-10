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
# TWO DELETION PATHS, NOT ONE, AND THEY ARE GUARDED DIFFERENTLY. The rule
# above governs the sweep, which only ever removes a directory it FOUND under
# the extensions directory. The destination wipe further down is the other
# one, and it removes a path this script CONSTRUCTS from the payload's own
# manifest — so what bounds it is not a manifest comparison but
# `single_component` below, which is why that check runs before anything is
# removed. Do not read the sweep's discipline as covering both.
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

# Is this manifest field ONE PATH COMPONENT? Non-empty, no separator, and
# neither of the two names that traverse.
#
# This is what keeps the destination inside the extensions directory, and it
# is load-bearing in a way the manifest-confirmed sweep below is not. The
# sweep only ever removes a directory it FOUND under `extensions`; the
# destination is CONSTRUCTED by interpolating these three fields, and it is
# wiped with `rm -rf` before the copy. So a manifest reading
# `"publisher": "../../victim"` resolves that wipe two levels above the
# extensions directory and takes whatever is there with it — reproduced, exit
# zero, no warning. Neither `npm ci` nor `tsc` validates the VSCode-specific
# identity fields, so a malformed source manifest reaches a release payload
# unremarked, and this same script is the developer entry point.
#
# VSCode's own identity grammar has no room for a separator, so nothing legal
# is refused here.
single_component() {
  case "$1" in
    "" | . | ..) return 1 ;;
    */*) return 1 ;;
  esac
  return 0
}

# The three identity fields of a payload, validated, into globals — the ONE
# derivation both entry points use, so `--print-identity` (which stamps the
# file the Scheme predicate reads) and the install cannot disagree about what
# this payload is called.
IDENT_PUBLISHER=""
IDENT_NAME=""
IDENT_VERSION=""

read_identity() {
  local dir="$1" manifest
  manifest="${dir}/package.json"
  [[ -f "$manifest" ]] || { echo "error: no package.json in ${dir}" >&2; exit 1; }
  IDENT_PUBLISHER="$(json_field "$manifest" publisher)"
  IDENT_NAME="$(json_field "$manifest" name)"
  IDENT_VERSION="$(json_field "$manifest" version)"
  if ! single_component "$IDENT_PUBLISHER" \
    || ! single_component "$IDENT_NAME" \
    || ! single_component "$IDENT_VERSION"; then
    echo "error: ${manifest} must name a publisher, name and version," >&2
    echo "       each a single path component (got" >&2
    echo "       '${IDENT_PUBLISHER}' / '${IDENT_NAME}' / '${IDENT_VERSION}')" >&2
    exit 1
  fi
}

payload_identity() {
  read_identity "$1"
  printf '%s.%s-%s\n' "$IDENT_PUBLISHER" "$IDENT_NAME" "$IDENT_VERSION"
}

main() {
  if [[ "${1:-}" == "--print-identity" ]]; then
    [[ $# -eq 2 ]] || usage
    payload_identity "$2"
    return
  fi

  [[ $# -ge 1 && $# -le 2 ]] || usage

  local payload extensions publisher name version target required
  payload="$1"
  if [[ -n "${2:-}" ]]; then
    extensions="$2"
  else
    extensions="${HOME:?HOME is unset; cannot locate ~/.vscode/extensions}/.vscode/extensions"
  fi
  [[ -d "$payload" ]] || { echo "error: no payload at ${payload}" >&2; exit 1; }
  payload="$(cd "$payload" && pwd -P)"

  read_identity "$payload"
  publisher="$IDENT_PUBLISHER"
  name="$IDENT_NAME"
  version="$IDENT_VERSION"
  target="${extensions}/${publisher}.${name}-${version}"

  # THE PAYLOAD MUST BE COMPLETE BEFORE ANYTHING IS REMOVED. Everything below
  # is destructive first and constructive second: the sweep removes every
  # installed copy of this extension, then the wipe removes the
  # current-version target, and only then does the copy run. A payload missing
  # one of the three things that copy needs therefore turns a failed upgrade
  # into LOSS OF THE WORKING VERSION that was already installed — reproduced
  # with a payload lacking only README.md, which removed a complete 0.9.0,
  # left a partial 1.0.0, and exited 1. A damaged bundle or an interrupted
  # `tsc` is enough to reach it.
  #
  # This is a completeness check, not a proof the copy will succeed: a disk
  # can still fill mid-copy, and the completion marker written last is what
  # covers that. What it buys is that a payload ALREADY KNOWN to be
  # unusable never gets far enough to destroy a usable installation.
  for required in package.json README.md out/src; do
    if [[ ! -r "${payload}/${required}" ]]; then
      echo "error: incomplete payload — ${payload}/${required} is missing or unreadable" >&2
      exit 1
    fi
  done

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
