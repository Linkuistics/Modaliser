# chooser-restyle-k7

**Kind:** work

## Goal

Restyle the standalone fuzzy-finder **chooser** to share the new **list-row
vocabulary** so it reads as one family with the overlay's embedded lists
(spec §8).

## Context

- Chooser CSS lives in `base.css` (287–451): `.chooser`, `.chooser-input`,
  `.chooser-row(.selected)`, `.match`, footer (389–405), header (74–103).
- `ui/chooser.scm` / `ui/chooser.js` render the panel; the footer already shows
  an item/match count + nav hints. The chooser shares theme tokens with the
  overlay but uses a `.chooser-row` **flex** layout (not the overlay grid).
- Depends on [[visual-skin-k5]] (shared tokens + named list-row classes) and
  benefits from [[list-cursor-k6]] (the `k` / `j` keys).

## Done when

- The chooser adopts the header band + IBM Plex + accent-focused input + accent
  fuzzy-match highlight + selected-row accent bar + separated footer (match count
  + nav hints), **reusing the shared list-row CSS** from [[visual-skin-k5]].
- Embedded lists and the chooser read as one visual family.
- The chooser's keyboard (arrows + `k j` + type-filter + `⏎`) stays intact.

## Notes

- Keep the chooser's own width and search-input structure — this is a **skin +
  footer** pass, not a rewrite. The chooser is the only Modaliser surface hosting
  a focused text input (see `CONTEXT.md` Chooser domain); don't disturb its paste
  / text-editing path.
