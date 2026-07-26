#!/usr/bin/env bash
# scripts/check-portable-surface.sh
#
# Audit what the user-facing Modaliser library tree is allowed to depend
# on. Two rules, both about the tree's import surface:
#
#   1. No host-specific (lispkit …) imports. The (modaliser …) library
#      tree must depend only on (scheme …), (srfi …), and other
#      (modaliser …) libraries — the portability contract documented in
#      docs/portability.md.
#
#   2. No (modaliser …-native) imports. A native capability that reaches
#      outward — spawning a subprocess, fetching a URL — is quarantined
#      behind an inert-by-default seam that only the host bootstrap
#      (root.scm) wires up, and the -native suffix is the marker for
#      the quarantined side — ADR-0023. The rule is stated over the
#      suffix rather than over a list of library names, so a new
#      quarantine needs no edit here: naming it -native is what enforces
#      it. A library importing the native form would silently re-open the
#      path that put 419 commands onto the developer's machine — and
#      fetched a third-party endpoint — during a green test run.
#
# Exit codes:
#   0  — clean
#   1  — at least one (lispkit …) or (modaliser …-native) reference
#         found in the user-facing tree
#   2  — target directory does not exist
#
# Usage:
#   ./scripts/check-portable-surface.sh
#
# Wire it into CI by running this script as a build/test step.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Sources/Modaliser/Scheme/lib/modaliser"

if [[ ! -d "$TARGET" ]]; then
  echo "check-portable-surface: $TARGET does not exist" >&2
  exit 2
fi

# -F: literal pattern, no regex surprises with parens.
# We match "(lispkit " (with the trailing space) to detect import
# forms. Prose comments must be phrased to avoid the literal pattern
# — e.g. write "the LispKit hashtable library" rather than
# "(lispkit hashtable)". The convention is enforced by this check
# itself: if a comment trips it, rephrase the comment.
if grep -rnF '(lispkit ' "$TARGET"; then
  echo
  echo "check-portable-surface: FAIL — (lispkit …) references found in $TARGET"
  echo "The (modaliser …) library tree must import only (scheme …),"
  echo "(srfi …), and other (modaliser …) libraries."
  echo "See docs/portability.md."
  exit 1
fi

# Rule 2: no quarantined native capability reaches the portable tree
# (ADR-0023). The -native suffix IS the marker, so this matches the
# suffix rather than a list of names — adding a quarantine is a naming
# decision, not an edit to this script. -E because the open paren needs
# escaping; the pattern deliberately stops before the closing paren so a
# prefixed import form trips it too. Prose in the tree must name these
# libraries as "the native shell library" / "the native HTTP library",
# never in parenthesised form — the same convention rule 1 imposes.
if grep -rnE '\(modaliser [a-z-]*-native' "$TARGET"; then
  echo
  echo "check-portable-surface: FAIL — a (modaliser …-native) library is imported in $TARGET"
  echo "Outward-reaching native capability is quarantined behind an inert"
  echo "seam — (modaliser shell) for spawning, (modaliser http) for fetching"
  echo "— whose runner only root.scm installs. Importing the native form"
  echo "bypasses that seam and lets a bare SchemeEngine() — every test —"
  echo "reach the developer's live tmux / zellij / terminal apps, or the"
  echo "public internet."
  echo "See docs/adr/0023-native-reach-is-host-installed.md."
  exit 1
fi

echo "check-portable-surface: OK — no (lispkit …) or (modaliser …-native) references in $TARGET"
