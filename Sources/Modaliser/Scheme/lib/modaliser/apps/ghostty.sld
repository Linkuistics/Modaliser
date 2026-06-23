;; (modaliser apps ghostty) — Ghostty host backend behind the
;; (modaliser terminal) façade. Implements 13/14 pane ops via the
;; Ghostty 1.3.0+ AppleScript surface plus detection and digit-jump
;; chip rendering.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser apps ghostty) ghostty:))
;;   (ghostty:register!)
;;
;; ─── Op surface (13/14) ────────────────────────────────────────────
;;
;; Native via AppleScript on the focused terminal of the front
;; window's selected tab:
;;   - focus-pane-{left,right,up,down}  → perform action "goto_split:<dir>"
;;   - split-pane-{left,right,up,down}  → split <focused> direction <dir>
;;   - focus-pane-by-digit              → focus <terminal whose id is ...>
;;   - toggle-pane-zoom                 → perform action "toggle_split_zoom"
;;
;; Unsupported (#f, by design):
;;   - move-pane-{left,right,up,down}
;;
;; Ghostty 1.3.1 exposes no `move_split` keybind action and no
;; AppleScript primitive that swaps two splits. `perform action` can't
;; invoke what doesn't exist, and `send key` can only fire actions the
;; user has bound — there's no fallback. Same shape as the WezTerm
;; gap: (terminal:supports-move-pane?) returns #f on Ghostty, so trees
;; that need move-pane gate on the predicate. When upstream lands
;; `move_split` (discussed for 1.4+) the four ops slot in as
;; `perform action "move_split:<dir>"` without changing the façade.
;;
;; ─── AppleScript-driven, with the `is running` guard ──────────────
;;
;; Every probe call is wrapped in `if application "Ghostty" is running
;; then ...` so background detection never auto-launches Ghostty via
;; Launch Services. The probe in 060 burnt that lesson — a naked
;; `tell application "Ghostty"` cold-started the .app.
;;
;; ─── Phantom-terminal caveat (1.3.1) ──────────────────────────────
;;
;; Ghostty 1.3.1 leaks terminal references: `terminals of selected tab
;; of front window` can return more entries than there are visible
;; panes. The investigation in
;; done/010-recover-design/notes/ghostty-current.md saw 7 terminals
;; for 3 splits; this implementation probe at 1.3.1 saw 9 terminals
;; for what was expected to be 3 visible panes (and 10 after another
;; split — the count is monotonic across the AppleScript session
;; lifetime). `goto_split:next` will cycle through every entry the
;; enumeration returns, real or not.
;;
;; The chip-rendering path is the only place this matters: chips are
;; painted off the AX-rect list (`AXScrollArea`, which reflects what
;; the user can actually see) and the digit→terminal map is truncated
;; to that count, so phantoms beyond the visible-pane count are
;; unreachable from a chip press. Directional ops are unaffected —
;; `perform action "goto_split:<dir>"` is the user's own daily
;; keybind, and Ghostty itself routes those between real panes only.
;;
;; ─── Foreground-command detection (honest v1) ─────────────────────
;;
;; Ghostty's AppleScript exposes `name` and `working directory` on a
;; terminal, but not the shell pid, tty, or foreground process. Until
;; upstream adds one of those — discussed but not shipped in 1.3.1 —
;; (detect-fg-command) returns the `name` field. For the default
;; Ghostty config that is the cwd; for shells that set OSC titles
;; including the running program (e.g. `precmd_functions` in zsh,
;; `PROMPT_COMMAND` in bash) it is the program name. Modaliser's nvim
;; suffix-hook bypasses this entirely via the running-nvim socket
;; scan in (modaliser terminal); tmux/zellij-inside-Ghostty rely on
;; the user's shell title to surface a "tmux"/"zellij" substring.
;;
;; ─── Chip rendering ────────────────────────────────────────────────
;;
;; Chips are `(modaliser hints)` overlay windows (CONTEXT "Chip"). The
;; per-pane rect comes from `(ax-find-elements
;; "com.mitchellh.ghostty" "AXScrollArea")` — the role Ghostty panes
;; expose in AX, assumed parallel to iTerm / WezTerm / Kitty. If AX
;; returns no scroll-areas (off-screen window, AX-trust unresolved)
;; the digit-pick mode skips hints-show; digits still dispatch via
;; the hidden key-range, matching the wezterm / tmux / zellij
;; fallback. The AX role assumption is verified at hand-verify time
;; per the leaf "Done when"; if Ghostty exposes a different role,
;; swap it here.

(define-library (modaliser apps ghostty)
  (export register!
          backend)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser util)
          (modaliser shell)
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser theming)
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!))
  (begin

    ;; ─── AppleScript wrapper ────────────────────────────────────────
    ;;
    ;; Every script is wrapped in an `is running` guard. When Ghostty
    ;; isn't running the body short-circuits to "" — same idiom as
    ;; (focused-iterm-tty) in (modaliser terminal). Callers compare
    ;; the trimmed return against "" to detect both "not running" and
    ;; "AppleScript error" cases without branching.
    ;;
    ;; The body argument is a complete AppleScript fragment that runs
    ;; *inside* `tell application "Ghostty"` — callers don't repeat
    ;; the tell block. Single-quote interpolation: the body must not
    ;; contain unescaped single quotes; all literal strings we pass
    ;; through here are static and quote-free.
    (define (osa body)
      (let* ((script (string-append
                       "if application \"Ghostty\" is running then "
                       "tell application \"Ghostty\" to "
                       body))
             (out (run-shell
                    (string-append "osascript -e '" script "' 2>/dev/null"))))
        (string-trim out)))

    ;; Boolean variant: AppleScript returns "true"/"false" textually;
    ;; "" (not running, or error) reads as #f.
    (define (osa-bool body)
      (string=? (osa body) "true"))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; focused-pane-id is the AppleScript `id` of the focused terminal
    ;; of the selected tab of the front window — a stable UUID string.
    ;; #f when Ghostty isn't running or has no front window.

    (define (focused-pane-id)
      (let ((out (osa
                   "id of focused terminal of selected tab of front window")))
        (if (string=? out "") #f out)))

    ;; detect-fg-command returns the focused terminal's `name`. Honest
    ;; v1: Ghostty 1.3.1 exposes no shell pid / tty / foreground-cmd
    ;; via AppleScript, and the cross-correlation that iTerm uses
    ;; (focused-pane → tty → ps -t) has no equivalent here. See
    ;; module header for the upgrade path when upstream lands one.
    (define (detect-fg-command)
      (let ((out (osa
                   "name of focused terminal of selected tab of front window")))
        (if (string=? out "") #f out)))

    ;; ─── Op primitives ──────────────────────────────────────────────

    ;; perform action returns boolean; we don't surface the boolean to
    ;; the façade (the existing shims thunkify the call). `false`
    ;; means "no neighbour in that direction" or "action no-op'd",
    ;; both indistinguishable from a binding-fired no-op the user
    ;; would have seen with their own keybind — same UX.
    (define (perform-action name)
      (osa-bool
        (string-append
          "perform action \"" name "\" on focused terminal of "
          "selected tab of front window")))

    (define (focus-pane-left)  (perform-action "goto_split:left"))
    (define (focus-pane-right) (perform-action "goto_split:right"))
    (define (focus-pane-up)    (perform-action "goto_split:up"))
    (define (focus-pane-down)  (perform-action "goto_split:down"))

    ;; split <focused> direction <dir> creates a new terminal on that
    ;; side and focuses it (Ghostty's default split behaviour). We
    ;; discard the returned terminal reference — the façade's surface
    ;; doesn't expose pane handles, and subsequent ops resolve via
    ;; `focused terminal of selected tab of front window`.
    (define (split-direction dir)
      (osa
        (string-append
          "split (focused terminal of selected tab of front window) "
          "direction " dir)))

    (define (split-pane-left)  (split-direction "left"))
    (define (split-pane-right) (split-direction "right"))
    (define (split-pane-up)    (split-direction "up"))
    (define (split-pane-down)  (split-direction "down"))

    ;; toggle_split_zoom is Ghostty's keybind action for the same UX
    ;; the user gets via cmd+enter (default). Stateless toggle per
    ;; ADR-0007. `perform action` is the supported entry point.
    (define (toggle-pane-zoom) (perform-action "toggle_split_zoom"))

    ;; ─── Digit-jump chip rendering ──────────────────────────────────
    ;;
    ;; Two-step snapshot at chip-mode entry:
    ;;
    ;;   1. AX rects from `AXScrollArea` give the visible per-pane
    ;;      geometry — pixel-exact, in walk order.
    ;;   2. AppleScript enumerates `id of every terminal of selected
    ;;      tab of front window`, truncated to the AX-rect count.
    ;;      That keeps the digit→id map aligned with what the user
    ;;      can actually see and discards phantom IDs the
    ;;      enumeration leaks (module header: "Phantom-terminal
    ;;      caveat").
    ;;
    ;; The assumption is that AX walk order and AppleScript element
    ;; order match for the *real* panes — both walk Ghostty's NSView
    ;; subview tree in the same depth-first order. Phantom IDs sit
    ;; at the end of the AppleScript list (Ghostty appends new
    ;; terminals; phantoms accumulated across earlier splits / prior
    ;; sessions are older), so truncating to N=visible-count keeps
    ;; the first N IDs aligned with the AX rects. If a future
    ;; Ghostty version interleaves them, this mapping needs to flip
    ;; to a per-id readback probe (focus + check focused-id; expensive).

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define (take-list xs n)
      (let loop ((xs xs) (n n) (acc '()))
        (cond
          ((or (null? xs) (<= n 0)) (reverse acc))
          (else (loop (cdr xs) (- n 1) (cons (car xs) acc))))))

    ;; Read the ordered list of terminal IDs in the front-tab.
    ;; `id of every terminal of ...` returns an AppleScript list which
    ;; osascript renders as `id1, id2, id3` (comma-space separated).
    ;; UUIDs don't contain commas so the split-and-trim parse is safe.
    ;; Same one-liner shape (modaliser apps iterm) uses for session
    ;; UUIDs.
    (define (list-pane-ids)
      (let ((trimmed (osa
                       (string-append
                         "id of every terminal of "
                         "selected tab of front window"))))
        (cond
          ((string=? trimmed "") '())
          (else
            (let loop ((parts (string-split trimmed ",")) (acc '()))
              (cond
                ((null? parts) (reverse acc))
                (else
                  (let ((s (string-trim (car parts))))
                    (loop (cdr parts)
                          (if (string=? s "") acc (cons s acc)))))))))))

    (define (host-rects)
      (ax-find-elements "com.mitchellh.ghostty" "AXScrollArea"))

    (define (chip-entries rects)
      (let ((labels (take-list digit-labels (length rects))))
        (let loop ((rs rects) (ls labels) (acc '()))
          (cond
            ((or (null? rs) (null? ls)) (reverse acc))
            (else
              (let* ((r (car rs))
                     (entry (list (cons 'handle #f)
                                  (cons 'x (cdr (assoc 'x r)))
                                  (cons 'y (cdr (assoc 'y r)))
                                  (cons 'w (cdr (assoc 'w r)))
                                  (cons 'h (cdr (assoc 'h r))))))
                (loop (cdr rs) (cdr ls)
                      (cons (cons (car ls) entry) acc))))))))

    ;; Snapshot at mode-enter so the digit-action closures don't
    ;; reissue the AppleScript enumeration at keystroke time. Same
    ;; pattern as wezterm / kitty / tmux / zellij.
    (define *current-ids* '())
    (define (set-current-ids! ids) (set! *current-ids* ids))

    (define (focus-by-digit d)
      (let ((idx (string->number d))
            (ids *current-ids*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (id (and (< zero-based (length ids))
                          (list-ref ids zero-based))))
            (when id
              (osa
                (string-append
                  "focus (first terminal of selected tab of front "
                  "window whose id is \"" id "\")")))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'ghostty-pane-digit
        'on-enter
        (lambda ()
          (let* ((rects (host-rects))
                 (n     (length rects))
                 (ids   (take-list (list-pane-ids) n)))
            (set-current-ids! ids)
            (cond
              ((and (pair? rects) (pair? ids))
               (let ((hints (ax-target-hints
                              (chip-entries rects)
                              (current-chip-theme 'normal))))
                 (hints-show hints)))
              (else
                ;; AX returned no rects, or AppleScript returned no
                ;; IDs (Ghostty not running, no front window) — skip
                ;; hints-show. Digits still dispatch via the range
                ;; below but the *current-ids* snapshot is empty so
                ;; they no-op cleanly.
                #f))))
        'on-leave (lambda () (hints-hide))
        (digit-range)))

    (define (focus-pane-by-digit)
      (enter-mode! 'ghostty-pane-digit))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — Ghostty has no provisioning step
    ;; in v1 (ADR-0005). All 13 ops work out of the box once Ghostty
    ;; itself is installed; the move-pane gap is honest (no action to
    ;; provision against), not configurable.

    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'ghostty "Ghostty" 'host "com.mitchellh.ghostty"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        ;; move-pane-{left,right,up,down}: #f. No Ghostty primitive
        ;; implements directional pane swap (see module-level notes).
        #f #f #f #f
        focus-pane-by-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode. Safe to call more
    ;; than once: register-backend! is last-write-wins on backend
    ;; symbol; define-tree replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!))))
