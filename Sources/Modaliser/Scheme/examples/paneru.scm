;; Modaliser example — paneru, the sliding window manager.
;;
;; ⚠️ THIS FILE IS NEVER LOADED. Modaliser reads exactly one user file,
;; `~/.config/modaliser/config.scm`; everything in `examples/` is
;; reference material that arrives fresh with each installed build (via
;; the `sys/` mirror) and sits there inert. Nothing you change here has
;; any effect, and nothing here can go stale in your config.
;;
;; It exists because paneru (karinushka/paneru) ships **no keyboard layer
;; of its own** — its `paneru.toml` `[bindings]` section is empty, and
;; this is how it gets one. A fresh install cannot seed it: seeding a
;; paneru screen on a machine without paneru would bind keys to a binary
;; that is not there, and which ops reach which keys is the one thing
;; Modaliser's libraries deliberately do not decide for you
;; (docs/adr/0021-decision-free-libraries.md).
;;
;; TO USE IT, one of:
;;
;;   • Copy the four marked ▶ blocks below into your own
;;     `~/.config/modaliser/config.scm` — the import, the alphabets, the
;;     two window screens with the branch that picks between them, and
;;     the line that splices the result into `(configuration …)`.
;;   • Or copy this whole file over `config.scm` as a starting point: it
;;     is a complete, working configuration in its own right (that is
;;     also how the test suite proves it still composes).
;;
;; Then relaunch Modaliser. F18 → "w" lands on the window screen: the
;; paneru one if paneru is installed, the stock layout one if not.
;;
;; Full design: docs/specs/paneru-window-management.md.
;; Surface reference: docs/reference/libraries.md → (modaliser wms paneru).

;; ▶ 1/4 — the import. `paneru:` prefix-style, because the bare op names
;; (`grow`, `shrink`, `center`) would otherwise read ambiguously beside
;; (modaliser window-actions)'s geometry ops.
(import (modaliser dsl)
        (modaliser configuration)
        (modaliser handoff)
        (modaliser keyboard)
        (modaliser app)
        (prefix (modaliser wms paneru)     paneru:)
        (prefix (modaliser window-actions) window:))

;; ▶ 2/4 — the jump alphabets. THREE of them, all yours: jump labels are
;; keys, and no library file may author a key (ADR-0021), so
;; `strip-provider` ships no defaults — omit an alphabet and you get
;; fewer labels, never a library-chosen letter.
;;
;;   'single-alphabet  one-key labels, in preference order
;;   'leader-alphabet  first key of a two-key label, once singles run out
;;   'second-alphabet  second key of a two-key label
;;
;; Escalation is automatic and minimal ((modaliser jump-labels)): with a
;; strip of ten or fewer, every label is one key and the leaders are
;; never touched. The eleventh window is what promotes a leader — and an
;; eleven-window strip is the case this design was measured against, not
;; a hypothetical one.
;;
;; ── THE PLANE RULE — the one trap in this surface ──
;;
;; Provider-supplied edges and static edges share ONE key space, and
;; `fsm-step!` takes static edges first. So any key you bind to an op
;; below is silently unreachable as a jump label: no error, no warning,
;; just a label drawn on a row that does nothing. The library cannot
;; enforce this — it authors neither side — so the split is your
;; contract to keep.
;;
;; This file splits the way herdr's jump space does: **labels on
;; lowercase, ops on capitals**. Any disjoint split works (digits for
;; labels, letters for ops; a reserved letter block; …). Overlap is the
;; trap, and it is the only one.
(define paneru-label-keys '("h" "j" "k" "l" "n" "m" "u" "i" "o" "p"))
(define paneru-leader-keys '("a" "s" "d" "f"))

;; ▶ 3/4 — the two window screens, and the branch that picks one.
;;
;; Both are ordinary values: `open` is a procedure, so a whole
;; drill-down can be built, named and spliced. Naming both (rather than
;; writing the `if` around two inline `open` calls) costs nothing at
;; runtime — the untaken one is simply an unused binding — and buys one
;; real thing: the example's paneru half is CONSTRUCTED whenever this
;; file loads, so `swift test`'s example load test catches an op that
;; stops existing. Under test no shell runner is installed, so
;; `installed?` is false and an inline `if` would never touch the paneru
;; branch at all.

;; The paneru screen. Every `paneru:`-prefixed name is one of the seven
;; ops exported by (modaliser wms paneru) — each one `paneru send-cmd …`
;; and nothing else. The keys, the labels and the grouping are
;; preference: rebind, drop or regroup any of it, subject only to the
;; plane rule above.
(define paneru-windows-screen
  (open "w" "Windows"

    ;; The Edge provider. It runs at come-to-rest, once per Visit,
    ;; BEFORE any render: query paneru → parse → join on window id
    ;; (ADR-0024) → assign labels. The listing below draws that same
    ;; snapshot, so the rows and the live labels cannot disagree, and a
    ;; label pressed faster than the overlay appears still works.
    ;;
    ;; 'panel-label names the panel of the NARROWED listing — the one a
    ;; two-key label's first press drills into. It is a second label
    ;; rather than a reuse of (panel "Strip" …) below because the two are
    ;; different renders, and both are yours to name.
    ;;
    ;; A fifth option, 'enumerate, overrides the window enumeration the
    ;; id join reads (default: the current-space accessibility sweep).
    ;; It is a test seam, NOT a performance knob — the wider, cached
    ;; alternative measured the same to within noise. Leave it alone.
    'provider (paneru:strip-provider
                'single-alphabet paneru-label-keys
                'leader-alphabet paneru-leader-keys
                'second-alphabet paneru-label-keys
                'panel-label     "Jump")

    ;; Relative motion along the strip. Capitals, per the plane rule.
    (panel "Move"
      (key "H" "Focus West" paneru:focus-west)
      (key "L" "Focus East" paneru:focus-east)
      (key "S" "Swap West"  paneru:swap-west)
      (key "D" "Swap East"  paneru:swap-east))

    ;; Width presets and re-centring. `grow`/`shrink` step through
    ;; paneru's own `preset_column_widths`, so what they do is set in
    ;; paneru.toml, not here.
    (panel "Size"
      (key "G" "Grow"   paneru:grow)
      (key "R" "Shrink" paneru:shrink)
      (key "C" "Center" paneru:center))

    ;; The Strip listing: the active virtual workspace's windows, in
    ;; strip order, each row carrying the jump label that focuses it.
    ;; Display-only — the labels dispatch through the provider's edges
    ;; above, not through this block.
    (panel "Strip"
      (paneru:strip-listing))))

;; NOTE — `'next 'self` is deliberately absent above, and it is the one
;; choice in this file worth making consciously.
;;
;; Adding it to Focus/Swap/Grow/Shrink re-arms the screen in place, so
;; one leader press starts a run of moves — the natural shape for
;; relative motion, and how the mux screens bind their focus ops. The
;; cost is that EVERY come-to-rest, a cyclic re-arm included, re-runs the
;; provider: measured at **≈34 ms** on an eleven-window strip in a
;; release build (14 ms subprocess spawn + 13 ms accessibility sweep +
;; 5 ms parse + 2 ms join), synchronously, before the next key is
;; handled.
;;
;; ≈34 ms per deliberate press is fine — re-entering the screen costs the
;; same provider run plus two extra keystrokes, so `'next 'self` is
;; strictly cheaper for a user who presses deliberately. What rules it
;; out of a REFERENCE composition is the tail, not the median: the
;; accessibility sweep ranges 8–29 ms warm and past 200 ms cold, and
;; Modaliser does not filter auto-repeat — so HOLDING Focus West queues
;; work faster than it drains and the strip keeps sliding after you let
;; go. Without `'next 'self` the machine has already left the screen and
;; the repeats cannot fire the op at all.
;;
;; So: add `'next 'self` if you press deliberately and want the run.
;; Don't if you hold keys down. The full measurement table, method and
;; ruling are in docs/specs/paneru-window-management.md decision 4.

;; The stock window screen, for when paneru is not installed. Nothing
;; about it is paneru-aware — it is the seeded configuration's own
;; Windows drill-down, reproduced here so the branch below has both
;; halves in view.
(define layout-windows-screen
  (open "w" "Windows"
    (panel #f (window:default-layout-block))
    (panel "Windows" (window:list-block 'chips? #t))))

;; The **Paneru-installed composition**: one `if`, taken ONCE at config
;; load (ADR-0018). It asks whether paneru is INSTALLED (`command -v
;; paneru`), never whether the daemon is up — a liveness test would make
;; the meaning of "w" depend on whether Modaliser or paneru won the
;; startup race. A daemon that is down degrades quietly instead: the
;; query answers nothing, the listing is empty, no label dispatches, and
;; the seven ops go nowhere. Start Modaliser first and nothing breaks.
(define windows-screen
  (if (paneru:installed?)
      paneru-windows-screen
      layout-windows-screen))

;; ─── The rest is a minimal host config, so this file stands alone ──

(define global-screen
  (screen 'global
    (panel "Applications"
      (key "t" "Terminal" (λ () (launch-app "iTerm"))))

    ;; ▶ 4/4 — the branch's result, spliced in as the "w" drill-down.
    ;; This is the whole integration: one name, wherever your own
    ;; Windows drill-down already sits.
    windows-screen))

(modaliser:start!
  (configuration
    (leaders
      (leader 'global F18)
      (leader 'local  F17))
    (overlay-delay 0.3)
    global-screen))
