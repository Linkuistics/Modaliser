;; (modaliser muxes tmux) — tmux mux backend behind the (modaliser terminal)
;; façade. Implements all 14 pane ops via the tmux CLI, plus detection
;; and digit-jump chip rendering.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser muxes tmux) tmux:))
;;   (tmux:register!)
;;
;; Once the iTerm (or any host) backend is also registered, ops dispatch
;; through (modaliser terminal) — when the focused host pane's foreground
;; command is "tmux", `(terminal:focus-pane-left)` resolves to this
;; backend's `tmux select-pane … -L`.
;;
;; Multi-session resolution. When several iTerm panes each
;; attach to a different tmux session, every CLI command targets the
;; session whose client is bound to the focused iTerm pane's tty. The
;; mapping comes from `tmux list-clients -F '#{client_tty} #{session_name}'`
;; — simpler and more direct than the pgrep+lsof recipe the façade
;; still exports as
;; `correlate-mux-client-to-host-tty` for backends without an equivalent
;; native query (zellij).
;;
;; Digit-jump chip rendering. Chips are `(modaliser hints)` overlay
;; windows, like every other backend (CONTEXT "Chip"). Rect derivation
;; takes the focused iTerm session's AX frame as the tmux canvas, reads
;; tmux's per-pane cell coords, and divides — no font query, no
;; host-specific cell-dim helper needed. For v1 this assumes a single
;; iTerm split (or the first one if multiple); multi-split iTerm + tmux
;; chip rendering is a known soft spot that a cross-cutting host
;; cell-dim helper will fix when a per-host leaf lands.

(define-library (modaliser muxes tmux)
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
          ;; The façade exports the 14 op names plus the predicates;
          ;; this module defines its own focus-pane-left etc. as the
          ;; record fields, so import only the machinery we need.
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!
                focused-iterm-tty
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where tmux lives), so every
    ;; shell-out is prefixed with the tool path. Same pattern as the
    ;; nvim helpers in (modaliser terminal).
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Multi-session resolution ───────────────────────────────────
    ;;
    ;; `tmux list-clients` returns one row per attached client with its
    ;; controlling tty and session. We match against the focused iTerm
    ;; pane's tty so subsequent commands target *that* session. Failure
    ;; modes that resolve to #f (no client matches, no host tty, query
    ;; fails) leave the target unspecified — tmux then acts on its
    ;; default-active session, which is the right behaviour for the
    ;; single-session common case.
    ;;
    ;; This is the tmux-native equivalent of the façade's pgrep+lsof
    ;; recipe; both produce the same answer, but tmux already knows
    ;; the (tty, session) pairing so there's no need to walk procfs.
    (define (session-for-host-tty)
      (let ((host-tty (focused-iterm-tty)))
        (and host-tty
             (let* ((out (run-shell
                           (string-append
                             path-prefix
                             "tmux list-clients -F "
                             "'#{client_tty} #{session_name}' 2>/dev/null")))
                    (lines (string-split out "\n")))
               (let loop ((ls lines))
                 (cond
                   ((null? ls) #f)
                   (else
                    (let* ((line (string-trim (car ls)))
                           (parts (string-split line " ")))
                      (cond
                        ((or (string=? line "") (null? parts) (null? (cdr parts)))
                         (loop (cdr ls)))
                        ((string=? (car parts) host-tty)
                         (car (cdr parts)))
                        (else (loop (cdr ls))))))))))))

    ;; Wraps a target spec. When session is #f we omit -t entirely so
    ;; tmux acts on the current/only session; when it resolves we pin
    ;; commands at that session. The resulting fragment is empty or
    ;; " -t <session>" (leading space included), ready for splicing
    ;; into a tmux command string. Use only for commands that don't
    ;; otherwise need a -t (select-pane direction, split-window,
    ;; display-message, list-panes, resize-pane -Z); commands that
    ;; target a specific pane go through `qualify-target` instead.
    (define (target-flag session)
      (if session (string-append " -t " session) ""))

    ;; Embeds the session in a pane-target spec. tmux accepts
    ;; `<session>:[window].<pane>` everywhere `-t` does, which avoids
    ;; emitting two `-t` flags (only the last wins, silently losing
    ;; session pinning in multi-session setups). Pass any tmux
    ;; pane-target string (`%3`, `{left-of}`, etc.); we wrap it.
    (define (qualify-target target)
      (let ((session (session-for-host-tty)))
        (if session
            (string-append session ":." target)
            target)))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; display-message reports a single field; combining it with
    ;; target-flag gives multi-session-safe queries. The pane id format
    ;; is %N (stable across the session's lifetime — see
    ;; done/.../notes/tmux.md "Pane IDs use %N"). Empty output (no
    ;; client, query failed) collapses to #f rather than empty string.
    (define (display-message field)
      (let* ((session (session-for-host-tty))
             (cmd     (string-append
                        path-prefix
                        "tmux display-message"
                        (target-flag session)
                        " -p '" field "' 2>/dev/null"))
             (out     (string-trim (run-shell cmd))))
        (if (string=? out "") #f out)))

    (define (focused-pane-id)
      (display-message "#{pane_id}"))

    (define (detect-fg-command)
      (display-message "#{pane_current_command}"))

    ;; ─── Op primitives ──────────────────────────────────────────────
    ;;
    ;; All 14 ops shell out through one `tmux-cmd` helper that prepends
    ;; the PATH and the session target. Discarding stderr keeps probe
    ;; noise out of the GUI app log when (rarely) tmux exits non-zero
    ;; for innocuous reasons (e.g. nothing to swap with at the edge of
    ;; the layout). The op recipes come from the recovery notes
    ;; (done/.../notes/tmux.md) — direction-flag conventions are tmux's
    ;; "split = result-layout-axis" naming: `-h` = vertical divider =
    ;; new pane to the right; `-v` = horizontal divider = new pane below;
    ;; `-b` puts the new pane BEFORE active (left / above).

    (define (tmux-cmd args)
      (let* ((session (session-for-host-tty))
             (cmd (string-append
                    path-prefix
                    "tmux " args (target-flag session) " 2>/dev/null")))
        (run-shell cmd)))

    ;; Focus.
    (define (focus-pane-left)  (tmux-cmd "select-pane -L"))
    (define (focus-pane-right) (tmux-cmd "select-pane -R"))
    (define (focus-pane-up)    (tmux-cmd "select-pane -U"))
    (define (focus-pane-down)  (tmux-cmd "select-pane -D"))

    ;; Split. Direction maps to tmux's "split axis = result layout":
    ;; user's "split left" wants a new pane LEFT of focused → vertical
    ;; divider (-h) with -b (before active).
    (define (split-pane-left)  (tmux-cmd "split-window -h -b"))
    (define (split-pane-right) (tmux-cmd "split-window -h"))
    (define (split-pane-up)    (tmux-cmd "split-window -v -b"))
    (define (split-pane-down)  (tmux-cmd "split-window -v"))

    ;; Move / swap. tmux 3.x's `{left-of}` / `{right-of}` / `{up-of}` /
    ;; `{down-of}` selectors swap with the directional neighbour. The
    ;; source pane defaults to "current" when -s is omitted; the swap
    ;; target is qualified with the session via `qualify-target` so we
    ;; emit a single -t (chaining two flags would silently lose the
    ;; session pinning).
    (define (swap-with target)
      (let* ((cmd (string-append
                    path-prefix
                    "tmux swap-pane -t '"
                    (qualify-target target)
                    "' 2>/dev/null")))
        (run-shell cmd)))
    (define (move-pane-left)  (swap-with "{left-of}"))
    (define (move-pane-right) (swap-with "{right-of}"))
    (define (move-pane-up)    (swap-with "{up-of}"))
    (define (move-pane-down)  (swap-with "{down-of}"))

    ;; Zoom. tmux's `resize-pane -Z` is a stateless toggle — the
    ;; required semantics. `window_zoomed_flag` exposes the current
    ;; state but we don't need it — the toggle is idempotent in shape.
    (define (toggle-pane-zoom)
      (tmux-cmd "resize-pane -Z"))

    ;; ─── Digit-jump chip rendering ──────────────────────────────────
    ;;
    ;; tmux's panes don't surface in macOS AX (tmux paints inside one
    ;; iTerm session view), so we synthesise chip rects:
    ;;
    ;;   1. tmux gives per-pane (left,top,width,height) in CELLS via
    ;;      list-panes format strings, plus the window's total cell
    ;;      grid via #{window_width}/#{window_height}.
    ;;   2. iTerm's focused AXScrollArea gives the pixel frame the tmux
    ;;      canvas occupies.
    ;;   3. cell_w = host_frame.w / window_width;
    ;;      cell_h = host_frame.h / window_height.
    ;;   4. chip rect = (host.x + pane_left*cell_w,
    ;;                   host.y + pane_top*cell_h,
    ;;                   pane_width*cell_w, pane_height*cell_h).
    ;;
    ;; v1 simplification: when iTerm has multiple AXScrollAreas (split
    ;; iTerm host) we take the first match. Multi-iTerm-split + tmux is
    ;; uncommon enough to defer until the cross-cutting host cell-dim
    ;; helper lands.

    ;; tmux gives ROWS like "%0 0 0 40 24" — pane_id then four ints.
    ;; Returns a list of (pane-id left top width height) lists; empty
    ;; on query failure.
    (define (list-panes)
      (let* ((session (session-for-host-tty))
             (cmd (string-append
                    path-prefix
                    "tmux list-panes"
                    (target-flag session)
                    " -F '#{pane_id} #{pane_left} #{pane_top} "
                    "#{pane_width} #{pane_height}' 2>/dev/null"))
             (out (run-shell cmd)))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let* ((line (string-trim (car lines)))
                     (parts (string-split line " ")))
                (if (or (string=? line "")
                        (< (length parts) 5))
                    (loop (cdr lines) acc)
                    (loop (cdr lines)
                          (cons (list (list-ref parts 0)
                                      (string->number (list-ref parts 1))
                                      (string->number (list-ref parts 2))
                                      (string->number (list-ref parts 3))
                                      (string->number (list-ref parts 4)))
                                acc)))))))))

    ;; "WxH" → (W H) numbers; #f if the shape doesn't match.
    (define (window-cell-grid)
      (let ((wh (display-message "#{window_width} #{window_height}")))
        (and wh
             (let ((parts (string-split wh " ")))
               (and (= (length parts) 2)
                    (let ((w (string->number (car parts)))
                          (h (string->number (cadr parts))))
                      (and w h (list w h))))))))

    ;; iTerm's focused-window AX query returns one alist per session
    ;; pane. v1 takes the first; see module-level comment on the
    ;; multi-split limitation.
    (define (host-frame)
      (let ((panes (ax-find-elements-named
                     "com.googlecode.iterm2" "AXScrollArea" "AXStaticText")))
        (and (pair? panes) (car panes))))

    ;; Build labelled-element entries for ax-target-hints. Labels come
    ;; from the same default 1..0 sequence iTerm uses for its own
    ;; pane chips (CONTEXT "Chip" — chips are visually uniform across
    ;; backends, so label vocabulary tracks the convention).
    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Number of elements taken from the head of `xs`. Used to truncate
    ;; the label sequence down to actual pane count without paying for
    ;; SRFI-1 `take` (LispKit's base list-ops only).
    (define (take-list xs n)
      (let loop ((xs xs) (n n) (acc '()))
        (cond
          ((or (null? xs) (<= n 0)) (reverse acc))
          (else (loop (cdr xs) (- n 1) (cons (car xs) acc))))))

    ;; Each labelled entry is (LABEL . ((handle . #f) (x . X) (y . Y)
    ;; (w . W) (h . H))) — same shape as ax-find-elements rows, so
    ;; `ax-target-hints` consumes it unchanged. The `handle` slot is
    ;; #f (no AX handle) because the action invokes select-pane by
    ;; %N id, not AX focus.
    (define (chip-entries panes host grid-w grid-h)
      (let ((hx (cdr (assoc 'x host)))
            (hy (cdr (assoc 'y host)))
            (hw (cdr (assoc 'w host)))
            (hh (cdr (assoc 'h host))))
        (let ((labels (take-list digit-labels (length panes))))
          (let loop ((ps panes) (ls labels) (acc '()))
            (cond
              ((or (null? ps) (null? ls)) (reverse acc))
              (else
                (let* ((p (car ps))
                       (pl (list-ref p 1))
                       (pt (list-ref p 2))
                       (x (+ hx (quotient (* pl hw) grid-w)))
                       (y (+ hy (quotient (* pt hh) grid-h)))
                       ;; w/h not consumed by ax-target-hints (it
                       ;; sizes chips from the theme), but included
                       ;; for shape parity with ax-find-elements rows.
                       (w (quotient (* (list-ref p 3) hw) grid-w))
                       (h (quotient (* (list-ref p 4) hh) grid-h))
                       (entry (list (cons 'handle #f)
                                    (cons 'x x) (cons 'y y)
                                    (cons 'w w) (cons 'h h))))
                  (loop (cdr ps) (cdr ls)
                        (cons (cons (car ls) entry) acc)))))))))

    ;; Snapshot taken at mode-enter — read once, used by both the chip
    ;; rendering pass and the digit-action closures. Storing in a
    ;; module-level box keeps the action thunks free of AX/CLI work at
    ;; keystroke time.
    (define *current-panes* '())
    (define (set-current-panes! ps) (set! *current-panes* ps))

    (define (focus-by-digit d)
      (let* ((idx (string->number d))
             (panes *current-panes*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (pane (and (< zero-based (length panes))
                            (list-ref panes zero-based))))
            (when pane
              (run-shell
                (string-append
                  path-prefix
                  "tmux select-pane -t '"
                  (qualify-target (car pane))
                  "' 2>/dev/null")))))))

    ;; The hidden key-range that handles the digit press — same shape
    ;; as `(modaliser apps iterm) pane-range`. Range is 1..0
    ;; (Modaliser's convention for "ten-key digit"); the chip list
    ;; above shows which numeric label sits on which pane.
    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    ;; Side-effect: rebuilds *current-panes*, computes chip entries,
    ;; and surfaces them via hints-show. on-leave hides them.
    (define (pane-digit-register!)
      (register-tree! 'tmux-pane-digit
        'on-enter
        (lambda ()
          (let* ((panes (list-panes))
                 (host  (host-frame))
                 (grid  (window-cell-grid)))
            (set-current-panes! panes)
            (cond
              ((and host grid (pair? panes))
               (let* ((entries (chip-entries panes host (car grid) (cadr grid)))
                      (hints   (ax-target-hints entries (current-chip-theme 'normal))))
                 (hints-show hints)))
              (else
                ;; Nothing to render (no host, no grid, or no panes
                ;; visible). Skip hints-show entirely so the overlay
                ;; isn't shown empty; digits still dispatch via the
                ;; range below, which is the same fallback the iTerm
                ;; pane-digit mode relies on.
                #f))))
        'on-leave (lambda () (hints-hide))
        (digit-range)))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — tmux has no provisioning step (no
    ;; config-file edits, no keybinding install). The CLI just works
    ;; out of the box, which is the property that earned tmux its full
    ;; 14/14 op surface.

    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'tmux "tmux" 'mux "tmux"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        'tmux-pane-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode. Safe to call more
    ;; than once: register-backend! is last-write-wins on backend
    ;; symbol; register-tree! replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!))))
