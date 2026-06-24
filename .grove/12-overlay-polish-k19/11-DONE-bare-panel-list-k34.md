# bare-panel-list-k34

**Kind:** work

## Goal

Two presentation fixes on a panel-embedded live list (the iTerm "Panes"/"Tabs"
lists, and — in the user's config — the Windows panel's list), flagged live by
the user on 2026-06-24 (verbatim): "Lists within panels don't need their own
framing. Also, they aren't consistently position[ed] vertically within the
panel."

1. **Drop the inner framing.** An embedded list renders today as a *box within a
   box*: `.panel-list` is a tinted, bordered, rounded inset (`--list-bg` +
   `--list-border` + `border-radius: var(--panel-radius)`, `margin: 0 8px 8px`,
   `padding: 5px 7px 6px`) sitting inside the panel card. The panel card already
   frames the content, so the inner frame is redundant. Strip it so the list
   rows sit directly in the panel (cf. `.panel--bare .panel-list` /
   `.panel-loose .panel-list`, which already do exactly this for the bare-diagram
   and loose paths — the inset chrome is dropped there). Decide whether this
   becomes the *default* for every panel-embedded list (likely — the box-in-box
   look is the same everywhere) rather than a per-panel opt-in.

2. **Anchor the list consistently (user clarified: "gap above the list varies").**
   The list starts at a different vertical offset from panel to panel — a
   list-only panel (Windows) hugs its header, while panels differ depending on
   what sits above the list (key-rows vs. nothing) and on the `.panel-list`
   inset margins + the `.list-caption` spacing. Make the list anchor flush under
   whatever precedes it (header or rows) so the gap reads identically across
   panels. Removing the inset margins (point 1) likely does most of this; verify
   the caption/`.panel-rows` spacing doesn't leave a residual inconsistency.

## Context / pointers

- Embedded-list CSS: `base.css` — `.panel-list` (the inset frame), the
  `.panel-list.block-window-list, .panel-list.block-iterm-panes { margin-top: 0 }`
  override, `.list-caption` (the "Panes"/"Windows" eyebrow + green live dot), and
  the precedents `.panel--bare .panel-list` / `.panel-loose .panel-list` that
  already strip the inset.
- Renderer: `ui/overlay.js` `renderPanelList` (wraps the block in
  `.panel-list block block-<type>`) and `renderPanel` (header → rows → list
  order); `ui/overlay.scm` `panel->json` (emits `"list"`).
- Block renderers that draw the rows inside the section:
  `lib/modaliser/blocks/window-list.{js,css}`, `iterm-panes`, `iterm-tabs`.
- Panels-with-lists to eyeball: iTerm "Panes" + "Tabs" (bundled
  `default-config.scm`), and the Windows panel in the user's
  `~/.config/modaliser/config.scm`.

## Done when

- A panel-embedded live list renders with **no inner frame** (no tint / border /
  rounded inset) — rows sit directly in the panel card.
- The list's vertical gap above is **consistent** across panels (anchored flush
  under the header/rows).
- `swift test` green; `./scripts/check-portable-surface.sh` green.
- **Live verify (needs the user):** `./scripts/install.sh`, Relaunch, open an
  iTerm overlay (Panes/Tabs) and the Windows overlay — embedded lists are
  unframed and sit at a consistent vertical offset.

## Notes

- Surfaced during the window-diagram-polish-k31 live review (2026-06-24);
  same overlay-polish-k19 node, independent of the diagram fixes.
- The bare-diagram (k22) and loose-region (k23) paths already strip the
  `.panel-list` inset — this generalises that treatment to the *framed* panel
  path, so check whether those rules and this one should converge on a single
  source instead of three near-duplicate strip blocks.
