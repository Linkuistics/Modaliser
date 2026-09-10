# configuration-exploration-k1
## Goal

Establish the scope, user scenarios, current-code baseline, and bounded research
questions for the requested exploration. Leave architecture and language choices
open for evidence-based comparison.

## Context

Read the root brief and `docs/research/configuration-exploration-context.md`.

## Done when

- The user's three research subjects and no-implementation constraint are recorded.
- The runtime scope and VS Code layout example are recorded in the user's terms.
- Current behavior is grounded in relevant source reads with limitations stated.
- Focused research tasks and their downstream design questions are concrete.

## Notes

The research scope is sufficiently established to proceed. Open architectural
questions are the subjects of the investigation, not choices the user must settle
before evidence exists. No implementation test seams are being accepted here.

## Decisions (running log)

The user requested research/design in a Grove, with no implementation. This
constrains every descendant session; even runnable prototypes require a later
change of scope.

Asked whether to compare replacing the Scheme runtime against adding a different
configuration language above it. The user chose: "Compare both approaches
(Recommended)". Both remain live alternatives.

The user supplied the VS Code example: "I'd like to able to split up the non-list
elements, and then group e.g. the editor list with the next/prev controls. Also the
layout changes depending on the list widths." Use that workflow across all
surveys and the proposed design.

The user answered the width-policy follow-up: "Keep groups stable; wrap or
truncate titles (Recommended)". Stable group placement is required when list
contents become wider. Wrapping versus truncation can remain configurable; do not
re-ask the resolved placement preference.
