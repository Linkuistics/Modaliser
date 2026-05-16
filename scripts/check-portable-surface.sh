#!/usr/bin/env bash
# scripts/check-portable-surface.sh
#
# Audit the user-facing Modaliser library tree for host-specific
# (lispkit …) imports. The (modaliser …) library tree must depend
# only on (scheme …), (srfi …), and other (modaliser …) libraries —
# that's the portability contract documented in docs/portability.md.
#
# Exit codes:
#   0  — clean
#   1  — at least one (lispkit …) reference found in the user-facing tree
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

echo "check-portable-surface: OK — no (lispkit …) references in $TARGET"
