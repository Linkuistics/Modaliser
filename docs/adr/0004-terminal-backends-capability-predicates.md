# Terminal-backends: capability predicates for cross-backend trees

The façade's 14 ops can be `#f` (unsupported) for the active backend
(e.g. `move-pane-*` on Ghostty 1.3.1; `toggle-pane-zoom` on Kitty;
all 14 on Alacritty when no mux is hosted inside). Calling an
unsupported op errors. To let one generic tree gate bindings by
backend support, `(modaliser terminal)` exports a small set of
capability predicates plus a universal introspection procedure:

- `(supports-splits?)` — true if the active backend implements all 12
  focus/split/move ops. Distinguishes splitting backends from
  detection-only (Alacritty alone, no mux inside).
- `(supports-move-pane?)` — true if `move-pane-{left,right,up,down}`
  are all supported. Distinguishes 14/14 backends from 13/14
  (WezTerm pre-configure-entry, Ghostty 1.3.1).
- `(supports-digit-jump?)` — true if `focus-pane-by-digit` is
  supported.
- `(supports-zoom?)` — true if `toggle-pane-zoom` is supported.
  False for Kitty in v1 (no native single-pane zoom) and for any
  detection-only context.
- `(supports? 'focus-pane-left)` — universal escape hatch for fine-
  grained gating; takes any of the 14 op symbols.

Predicates evaluate against `(active-backend)` *at call time* — same
resolution path as the ops themselves. This means trees built via the
existing `set-local-context-suffix!` rebuild-per-press pattern see
current capabilities; static trees built once at config load see
load-time capabilities. The PRD documents this explicitly to prevent
silent-bake-in bugs.

The chosen grain (3 coarse predicates + universal introspection) is
the smallest set that maps to actual real-world differences across
backends; finer predicates would proliferate without paying for
themselves. Backend-specific introspection (e.g. "are we running on
Ghostty ≥ 1.3.0?") is out of scope — capability predicates report
what works, not why.
