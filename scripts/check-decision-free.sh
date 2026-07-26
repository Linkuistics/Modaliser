#!/usr/bin/env bash
# scripts/check-decision-free.sh
#
# Enforce ADR-0021: a (modaliser …) library may hold a FACILITY —
# anything whose correctness is fixed by the tool it wraps or the
# machinery it implements — but never a DECISION, anything whose
# correctness is fixed only by the user's preference.
#
# The operational test is mechanical: NO FILE UNDER
# Sources/Modaliser/Scheme/lib/modaliser AUTHORS A KEY OR A LABEL.
# A `(key "z" "Zoom" …)` names both, and which op sits on which key
# under which label is preference; a `(key-range "1.." "Pane <n>" …)`
# is a digit range whose shape herdr fixes, and a `(panel "Focus" …)`
# is presentation, so neither is matched. A constructor that takes its
# key and label as ARGUMENTS also passes — correctly, because the
# decision then belongs to the caller.
#
# STRICT ZERO. This was a ratchet while the contract was being paid
# off — introduced at 136 (the drift that had accumulated under a
# doctrine already saying wiring belonged in libraries), lowered by
# each leaf, reaching 0 at apps-own-their-bindings-k47. The ceiling
# is gone: a single authored key or label under lib/modaliser fails
# the check, exactly as a single `(lispkit …)` import fails
# check-portable-surface.sh. Do not reintroduce a ceiling — the
# ratchet was migration scaffolding, not part of the contract.
#
# Out of scope by design: default-config.scm and Scheme/examples/*.scm.
# Authoring keys is precisely their point — they are the user-space
# side of this contract, not a violation of it. Neither lives under
# lib/modaliser, so the scope below already excludes them.
#
# Exit codes:
#   0  — clean
#   1  — at least one authored key or label in the library tree
#   2  — target directory does not exist
#
# Usage:
#   ./scripts/check-decision-free.sh
#
# Wire it into CI beside check-portable-surface.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/Sources/Modaliser/Scheme/lib/modaliser"

# A key and a label as adjacent string literals, after comments are
# stripped so a doc comment quoting a binding never counts.
PATTERN='\((key|keys|group|open) +"[^"]*" +"'

if [[ ! -d "$TARGET" ]]; then
  echo "check-decision-free: $TARGET does not exist" >&2
  exit 2
fi

# Report the offending LINES, not per-file counts: with no ceiling
# left there is no number to compare against, only sites to fix.
# `sed 's/;;.*//'` blanks comment tails rather than deleting lines, so
# grep -n line numbers still point at the real source lines.
offenders=()
while IFS= read -r file; do
  while IFS= read -r hit; do
    offenders+=("${file#"$ROOT"/}:$hit")
  done < <(sed 's/;;.*//' "$file" | grep -nE "$PATTERN" || true)
done < <(find "$TARGET" -name '*.sld' | sort)

if [[ "${#offenders[@]}" -gt 0 ]]; then
  printf '%s\n' "${offenders[@]}"
  echo
  echo "check-decision-free: FAIL — ${#offenders[@]} authored key/label" \
       "decision(s) in" >&2
  echo "$TARGET." >&2
  echo >&2
  echo "A library may not choose a key or a label. Export the op and let" >&2
  echo "the configuration bind it; see docs/adr/0021-decision-free-libraries.md." >&2
  exit 1
fi

echo "check-decision-free: OK — no authored key/label decisions in $TARGET"
