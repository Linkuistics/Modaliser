;; (modaliser muxes zellij) — zellij mux backend behind the (modaliser
;; terminal) façade. Implements all 14 pane ops via the `zellij action`
;; CLI, plus detection and digit-jump chip rendering.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser muxes zellij) zellij:))
;;   (zellij:register!)
;;
;; Once the iTerm (or any host) backend is also registered, ops dispatch
;; through (modaliser terminal) — when the focused host pane's foreground
;; command is "zellij", `(terminal:focus-pane-left)` resolves to this
;; backend's `zellij action move-focus left`.
;;
;; Multi-session resolution (ADR-0006). zellij's own `list-clients`
;; doesn't expose client ttys, so we use the façade's
;; `correlate-mux-client-to-host-tty` helper (pgrep + lsof) to find the
;; zellij client process whose controlling tty matches the focused host
;; pane, then read its argv via `ps -p PID -o args=` to recover the
;; session name. Single-session is the common, trivial case; multi-
;; session falls back to the default session if the correlation or argv
;; parse fails (zellij then targets its only / most-recent session,
;; which is the right behaviour for single-session setups).
;;
;; Digit-jump chip rendering. Chips are `(modaliser hints)` overlay
;; windows, like every other backend (CONTEXT "Chip"). Rect derivation
;; takes the focused iTerm session's AX frame as the zellij canvas,
;; computes the cell grid from all visible panes (including tab-bar /
;; status-bar plugin rows that occupy the same canvas), and uses
;; zellij's per-pane (pane_x, pane_y, pane_columns, pane_rows) — no
;; font query, no host-specific cell-dim helper needed. For v1 this
;; assumes iTerm-as-host (matching tmux); the cross-cutting host
;; cell-dim helper called out in the PRD will lift this when a non-
;; iTerm per-host leaf lands.

(define-library (modaliser muxes zellij)
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
                register-backend!
                focused-iterm-tty
                correlate-mux-client-to-host-tty
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where zellij lives), so every
    ;; shell-out is prefixed with the tool path. Same pattern as tmux
    ;; and the nvim helpers in (modaliser terminal).
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Multi-session resolution ───────────────────────────────────
    ;;
    ;; zellij's `list-clients` doesn't expose per-client ttys, so we
    ;; lean on the façade's `correlate-mux-client-to-host-tty` which
    ;; pgreps zellij client processes and matches each one's fd 0 tty
    ;; against the focused host pane's tty (ADR-0006). That gives us a
    ;; pid; we then read its argv to recover the session name.
    ;;
    ;; Argv shapes zellij clients take in practice:
    ;;   zellij                            (default — single session)
    ;;   zellij --session NAME ...
    ;;   zellij attach NAME
    ;;   zellij attach -c NAME             (-c = create if missing)
    ;;
    ;; The awk below scans the args linearly and prints the first
    ;; session-name token it finds, or nothing. An empty result feeds
    ;; back as #f → omit the --session flag → zellij targets the
    ;; default/only session, the right fallback for single-session.

    (define (session-name-for-pid pid)
      (let* ((cmd (string-append
                    path-prefix
                    "ps -p " pid " -o args= 2>/dev/null | "
                    "awk '{ "
                    "  for (i=1; i<=NF; i++) { "
                    "    if ($i == \"--session\" && i<NF) { print $(i+1); exit } "
                    "    if ($i == \"attach\") { "
                    "      for (j=i+1; j<=NF; j++) "
                    "        if (substr($j,1,1) != \"-\") { print $j; exit } "
                    "      exit "
                    "    } "
                    "  } "
                    "}'"))
             (out (string-trim (run-shell cmd))))
        (if (string=? out "") #f out)))

    (define (session-for-host-tty)
      (let* ((host-tty (focused-iterm-tty))
             (pid (and host-tty
                       (correlate-mux-client-to-host-tty
                         host-tty "^zellij"))))
        (and pid (session-name-for-pid pid))))

    ;; The `--session NAME` prefix fragment for a zellij CLI invocation.
    ;; Empty when no session resolves (zellij then targets its default).
    ;; Unlike tmux's trailing `-t`, zellij requires --session BEFORE the
    ;; action subcommand, so this is a *prefix* helper.
    (define (session-flag session)
      (if session (string-append "--session " session " ") ""))

    ;; ─── Pane-list parser ───────────────────────────────────────────
    ;;
    ;; `zellij action list-panes -j -a` emits a flat JSON array. We
    ;; don't want a JSON dep, so awk linearly turns each object into a
    ;; single space-separated line:
    ;;
    ;;   <id> <foc 0|1> <plug 0|1> <flot 0|1> <cmd|-> <x> <y> <cols> <rows>
    ;;
    ;; `pane_command` may be absent (plugins, freshly-created panes
    ;; before the shell registers); we substitute "-" so columns
    ;; remain positional. Spaces in pane_command (e.g. `vim foo.txt`)
    ;; are collapsed to `_` so the output stays one row per pane.

    (define parse-script
      (string-append
        "awk '"
        "BEGIN { in_obj=0 } "
        "/^  \\{[[:space:]]*$/ { "
        "  in_obj=1; id=\"\"; foc=\"\"; plug=\"\"; flot=\"\"; "
        "  cmd=\"-\"; x=\"\"; y=\"\"; c=\"\"; r=\"\"; next "
        "} "
        "/^  \\},?[[:space:]]*$/ { "
        "  if (in_obj) "
        "    printf \"%s %s %s %s %s %s %s %s %s\\n\", "
        "      id, foc, plug, flot, cmd, x, y, c, r; "
        "  in_obj=0; next "
        "} "
        "in_obj { "
        "  if      ($0 ~ /^    \"id\":/)           { match($0,/-?[0-9]+/); id   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"is_plugin\":/)    { plug = ($0 ~ /true/) ? \"1\" : \"0\" } "
        "  else if ($0 ~ /^    \"is_focused\":/)   { foc  = ($0 ~ /true/) ? \"1\" : \"0\" } "
        "  else if ($0 ~ /^    \"is_floating\":/)  { flot = ($0 ~ /true/) ? \"1\" : \"0\" } "
        "  else if ($0 ~ /^    \"pane_x\":/)       { match($0,/-?[0-9]+/); x    = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"pane_y\":/)       { match($0,/-?[0-9]+/); y    = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"pane_columns\":/) { match($0,/-?[0-9]+/); c    = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"pane_rows\":/)    { match($0,/-?[0-9]+/); r    = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"pane_command\":/) { "
        "    s = $0; sub(/^[^\"]*\"pane_command\":[[:space:]]*\"/, \"\", s); "
        "    sub(/\",?[[:space:]]*$/, \"\", s); gsub(/ /, \"_\", s); cmd = s "
        "  } "
        "}"
        "'"))

    ;; Returns a list of pane records, one per JSON object in the array.
    ;; Each record is the 9-tuple list (id foc plug flot cmd x y cols rows)
    ;; with id/foc/plug/flot/cmd as strings and the four coords as numbers
    ;; (or #f on missing). Empty on query failure (zellij not running,
    ;; session resolution failed in a way zellij rejects, etc.).
    (define (list-panes-raw)
      (let* ((session (session-for-host-tty))
             (cmd (string-append
                    path-prefix
                    "zellij " (session-flag session)
                    "action list-panes -j -a 2>/dev/null | "
                    parse-script))
             (out (run-shell cmd)))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let* ((line (string-trim (car lines)))
                     (parts (string-split line " ")))
                (if (or (string=? line "") (< (length parts) 9))
                    (loop (cdr lines) acc)
                    (loop (cdr lines)
                          (cons (list (list-ref parts 0)
                                      (list-ref parts 1)
                                      (list-ref parts 2)
                                      (list-ref parts 3)
                                      (list-ref parts 4)
                                      (string->number (list-ref parts 5))
                                      (string->number (list-ref parts 6))
                                      (string->number (list-ref parts 7))
                                      (string->number (list-ref parts 8)))
                                acc)))))))))

    (define (pane-id p)     (list-ref p 0))
    (define (pane-foc p)    (list-ref p 1))
    (define (pane-plug p)   (list-ref p 2))
    (define (pane-flot p)   (list-ref p 3))
    (define (pane-cmd p)    (list-ref p 4))
    (define (pane-x p)      (list-ref p 5))
    (define (pane-y p)      (list-ref p 6))
    (define (pane-cols p)   (list-ref p 7))
    (define (pane-rows p)   (list-ref p 8))

    ;; A pane is a "terminal" pane (one we render chips on and route ops
    ;; to) when both is_plugin and is_floating are false. The first-run
    ;; "About Zellij" overlay is floating; the tab-bar / status-bar /
    ;; alt-nav / link plugins all set is_plugin (notes/zellij.md).
    (define (terminal-pane? p)
      (and (string=? (pane-plug p) "0")
           (string=? (pane-flot p) "0")))

    (define (list-filter pred xs)
      (let loop ((xs xs) (acc '()))
        (cond
          ((null? xs)      (reverse acc))
          ((pred (car xs)) (loop (cdr xs) (cons (car xs) acc)))
          (else            (loop (cdr xs) acc)))))

    (define (list-find pred xs)
      (cond
        ((null? xs) #f)
        ((pred (car xs)) (car xs))
        (else (list-find pred (cdr xs)))))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; `focused-pane-id` returns the zellij pane reference in the form
    ;; the `focus-pane-id` action consumes: "terminal_<id>". Pane ids
    ;; are sparse (the recovery probe yielded 0, 3 — id 1, 2, 4 went to
    ;; plugins and a floating overlay), so we treat the id as opaque.

    (define (focused-terminal-pane)
      (list-find (lambda (p)
                   (and (terminal-pane? p)
                        (string=? (pane-foc p) "1")))
                 (list-panes-raw)))

    (define (focused-pane-id)
      (let ((p (focused-terminal-pane)))
        (and p (string-append "terminal_" (pane-id p)))))

    ;; pane_command shows up as the absolute path the shell was launched
    ;; with (e.g. "/bin/zsh") plus whatever it execs into. The façade's
    ;; descent step matches mux backends by basename ("tmux", "zellij"),
    ;; so we strip leading directory components — same convention as the
    ;; `ps`-derived results elsewhere in the project.
    (define (basename path)
      (let loop ((i (- (string-length path) 1)))
        (cond
          ((< i 0) path)
          ((char=? (string-ref path i) #\/)
           (substring path (+ i 1) (string-length path)))
          (else (loop (- i 1))))))

    (define (detect-fg-command)
      (let ((p (focused-terminal-pane)))
        (and p
             (let ((c (pane-cmd p)))
               (and c (not (string=? c "-")) (basename c))))))

    ;; ─── Op primitives ──────────────────────────────────────────────
    ;;
    ;; All 14 ops shell out via one `zellij-action` helper that prepends
    ;; the PATH and the --session prefix. Op recipes come from the
    ;; recovery notes (notes/zellij.md):
    ;;   focus  → `action move-focus <dir>`
    ;;   split  → `action new-pane -d <dir>` (all four dirs work despite
    ;;            the --help text claiming only right/down — recovery
    ;;            note "Crucial finding".)
    ;;   move   → `action move-pane <dir>` (swaps with neighbour)
    ;;   zoom   → `action toggle-fullscreen` (verified live in probe)

    (define (zellij-action args)
      (let* ((session (session-for-host-tty))
             (cmd (string-append
                    path-prefix
                    "zellij " (session-flag session)
                    "action " args " 2>/dev/null")))
        (run-shell cmd)))

    (define (focus-pane-left)  (zellij-action "move-focus left"))
    (define (focus-pane-right) (zellij-action "move-focus right"))
    (define (focus-pane-up)    (zellij-action "move-focus up"))
    (define (focus-pane-down)  (zellij-action "move-focus down"))

    (define (split-pane-left)  (zellij-action "new-pane -d left"))
    (define (split-pane-right) (zellij-action "new-pane -d right"))
    (define (split-pane-up)    (zellij-action "new-pane -d up"))
    (define (split-pane-down)  (zellij-action "new-pane -d down"))

    (define (move-pane-left)   (zellij-action "move-pane left"))
    (define (move-pane-right)  (zellij-action "move-pane right"))
    (define (move-pane-up)     (zellij-action "move-pane up"))
    (define (move-pane-down)   (zellij-action "move-pane down"))

    (define (toggle-pane-zoom) (zellij-action "toggle-fullscreen"))

    ;; ─── Digit-jump chip rendering ──────────────────────────────────
    ;;
    ;; Same scheme as tmux: iTerm's focused AXScrollArea gives the
    ;; pixel frame the zellij canvas occupies; we synthesise per-pane
    ;; rects from cell coords. The grid here is the union of ALL panes
    ;; (terminal + tab-bar / status-bar plugin rows that share the
    ;; canvas), so the cell-pixel ratio matches what the user sees.
    ;; Chips render only on terminal panes.
    ;;
    ;; v1 simplification (parallel to tmux): when iTerm has multiple
    ;; AXScrollAreas (split iTerm host) we take the first match.

    (define (max-of xs)
      (let loop ((xs xs) (m 0))
        (cond
          ((null? xs) m)
          ((and (number? (car xs)) (> (car xs) m))
           (loop (cdr xs) (car xs)))
          (else (loop (cdr xs) m)))))

    ;; grid_cols = max(pane_x + pane_columns) across all panes;
    ;; grid_rows = max(pane_y + pane_rows). Falls back to #f when the
    ;; list is empty or any pane has missing coords.
    (define (compute-grid panes)
      (and (pair? panes)
           (let ((cols (max-of (map (lambda (p)
                                      (and (pane-x p) (pane-cols p)
                                           (+ (pane-x p) (pane-cols p))))
                                    panes)))
                 (rows (max-of (map (lambda (p)
                                      (and (pane-y p) (pane-rows p)
                                           (+ (pane-y p) (pane-rows p))))
                                    panes))))
             (and (> cols 0) (> rows 0) (list cols rows)))))

    (define (host-frame)
      (let ((panes (ax-find-elements-named
                     "com.googlecode.iterm2" "AXScrollArea" "AXStaticText")))
        (and (pair? panes) (car panes))))

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define (take-list xs n)
      (let loop ((xs xs) (n n) (acc '()))
        (cond
          ((or (null? xs) (<= n 0)) (reverse acc))
          (else (loop (cdr xs) (- n 1) (cons (car xs) acc))))))

    ;; Each labelled entry mirrors the shape `ax-find-elements` returns
    ;; ((handle . #f) (x . X) (y . Y) (w . W) (h . H)) so ax-target-hints
    ;; consumes it unchanged. handle is #f — the action invokes
    ;; focus-pane-id by terminal_<id>, not via AX focus.
    (define (chip-entries terminal-panes host grid-w grid-h)
      (let ((hx (cdr (assoc 'x host)))
            (hy (cdr (assoc 'y host)))
            (hw (cdr (assoc 'w host)))
            (hh (cdr (assoc 'h host))))
        (let ((labels (take-list digit-labels (length terminal-panes))))
          (let loop ((ps terminal-panes) (ls labels) (acc '()))
            (cond
              ((or (null? ps) (null? ls)) (reverse acc))
              (else
                (let* ((p (car ps))
                       (x (+ hx (quotient (* (pane-x p) hw) grid-w)))
                       (y (+ hy (quotient (* (pane-y p) hh) grid-h)))
                       (w (quotient (* (pane-cols p) hw) grid-w))
                       (h (quotient (* (pane-rows p) hh) grid-h))
                       (entry (list (cons 'handle #f)
                                    (cons 'x x) (cons 'y y)
                                    (cons 'w w) (cons 'h h))))
                  (loop (cdr ps) (cdr ls)
                        (cons (cons (car ls) entry) acc)))))))))

    ;; Snapshot taken at mode-enter so the digit-action closures don't
    ;; reissue the JSON query / awk parse at keystroke time. Same
    ;; pattern as tmux's *current-panes*.
    (define *current-terminal-panes* '())
    (define (set-current-terminal-panes! ps) (set! *current-terminal-panes* ps))

    (define (focus-by-digit d)
      (let ((idx (string->number d))
            (panes *current-terminal-panes*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (p (and (< zero-based (length panes))
                         (list-ref panes zero-based))))
            (when p
              ;; `focus-pane-id` accepts both bare numeric ids (`0`) and
              ;; the prefixed form (`terminal_0`); we send the prefixed
              ;; form for symmetry with `focused-pane-id` and to avoid
              ;; collision with plugin / floating ids that share the same
              ;; numeric space (ids 0 and 3 in the recovery probe were
              ;; terminal panes; 1, 2, 4 went to plugins / floating).
              (run-shell
                (string-append
                  path-prefix
                  "zellij " (session-flag (session-for-host-tty))
                  "action focus-pane-id terminal_"
                  (pane-id p)
                  " 2>/dev/null")))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'zellij-pane-digit
        'on-enter
        (lambda ()
          (let* ((all-panes (list-panes-raw))
                 (terminals (list-filter terminal-pane? all-panes))
                 (host      (host-frame))
                 (grid      (compute-grid all-panes)))
            (set-current-terminal-panes! terminals)
            (cond
              ((and host grid (pair? terminals))
               (let* ((entries (chip-entries terminals host
                                             (car grid) (cadr grid)))
                      (hints   (ax-target-hints entries
                                                (current-chip-theme 'normal))))
                 (hints-show hints)))
              (else
                ;; Nothing to render (no host AX, no panes, or grid
                ;; computation failed). Skip hints-show; digits still
                ;; dispatch via the range below — the same fallback the
                ;; iTerm / tmux pane-digit modes rely on.
                #f))))
        'on-leave (lambda () (hints-hide))
        (digit-range)))

    (define (focus-pane-by-digit)
      (enter-mode! 'zellij-pane-digit))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — zellij has no provisioning step (no
    ;; config-file edits, no keybinding install). The `action` CLI just
    ;; works out of the box, which is the property that earned zellij
    ;; its full 14/14 surface in the PRD.

    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'zellij "zellij" 'mux "zellij"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        focus-pane-by-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode. Safe to call more
    ;; than once: register-backend! is last-write-wins on backend
    ;; symbol; register-tree! replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!))))
