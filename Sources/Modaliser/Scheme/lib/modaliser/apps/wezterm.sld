;; (modaliser apps wezterm) — WezTerm host backend behind the
;; (modaliser terminal) façade. Implements 13/14 pane ops via the
;; `wezterm cli` plus detection and digit-jump chip rendering.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser apps wezterm) wezterm:))
;;   (wezterm:register!)
;;
;; ─── Op surface (13/14) ────────────────────────────────────────────
;;
;; Native via `wezterm cli`:
;;   - focus-pane-{left,right,up,down}  → activate-pane-direction
;;   - split-pane-{left,right,up,down}  → split-pane --{left,right,top,bottom}
;;   - focus-pane-by-digit              → list + activate-pane --pane-id
;;   - toggle-pane-zoom                 → zoom-pane --toggle
;;
;; Unsupported (#f, by design):
;;   - move-pane-{left,right,up,down}
;;
;; WezTerm exposes no directional pane-swap primitive — not in the CLI
;; (`activate-pane-direction` is focus-only, `adjust-pane-size` is
;; resize, `split-pane --move-pane-id` moves into a *new* split), not
;; in default keybinds (`RotatePanes` is global Clockwise / CCW only),
;; and not in the Lua pane API. A `configure-entry` was originally
;; planned (ADR-0005) but the re-probe at implementation time found no
;; Lua action the keybind could call, so move-pane is honestly absent.
;; (terminal:supports-move-pane?) returns #f on WezTerm; trees that
;; need move-pane bindings gate on the predicate.
;;
;; The re-probe also found `wezterm cli zoom-pane --toggle` (added
;; post the recovery notes), so toggle-pane-zoom is CLI-native instead
;; of the keystroke-proxy ADR-0007 originally specified.
;;
;; ─── Chip rendering ────────────────────────────────────────────────
;;
;; Chips are `(modaliser hints)` overlay windows (CONTEXT "Chip").
;; WezTerm's JSON gives per-pane (left_col, top_row, size.cols,
;; size.rows) in cells and (size.pixel_width, size.pixel_height) so
;; the cell-pixel ratio is direct — no font query needed. To turn
;; cell coords into screen rects we still need the WezTerm GUI
;; window's screen origin: queried via (ax-find-elements
;; "com.github.wez.wezterm" "AXScrollArea") — the role WezTerm panes
;; expose in AX, parallel to iTerm. If AX doesn't return a frame
;; (off-screen window, no GUI panes registered yet) the digit-pick
;; mode skips hints-show; digits still dispatch via the hidden
;; key-range, matching the tmux / zellij fallback. The AX role
;; assumption is verified at hand-verify time per the leaf "Done
;; when"; if WezTerm exposes a different role, swap it here.

(define-library (modaliser apps wezterm)
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
                tty-foreground-command
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where wezterm lives), so every
    ;; shell-out is prefixed with the tool path. Same pattern as tmux,
    ;; zellij, and the nvim helpers in (modaliser terminal).
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; The CLI defaults to the GUI socket (correct for the user's daily
    ;; case: an actual WezTerm window). The `--prefer-mux` flag is for
    ;; headless probing only and is intentionally not used here.
    (define (wezterm-cli args)
      (run-shell
        (string-append
          path-prefix
          "wezterm cli " args " 2>/dev/null")))

    ;; ─── Pane-list parser ───────────────────────────────────────────
    ;;
    ;; `wezterm cli list --format json` emits a flat JSON array, one
    ;; object per pane across all windows / tabs. Same no-JSON-dep
    ;; rationale as zellij: awk turns each object into a single
    ;; space-separated line so Scheme can split-by-space, no parser
    ;; needed.
    ;;
    ;;   <pane_id> <is_active 0|1> <left_col> <top_row> <cols> <rows>
    ;;   <pixel_w> <pixel_h> <tty>
    ;;
    ;; tty_name is `/dev/ttysNNN` (no spaces); pane_id and the coords
    ;; are integers. The parser is conservative — any field that didn't
    ;; populate (rare; only when JSON shape drifts) lands as "-" and the
    ;; row is dropped by the caller's column count check.

    (define parse-script
      (string-append
        "awk '"
        "BEGIN { in_obj=0; depth=0 } "
        ;; Track brace depth so nested `size` object doesn't confuse the
        ;; per-pane boundary detection. Top-level pane objects are at
        ;; depth 1 (depth 0 = the outer array).
        "{ "
        "  for (i=1; i<=length($0); i++) { "
        "    c=substr($0,i,1); "
        "    if (c==\"{\") depth++; "
        "    if (c==\"}\") depth--; "
        "  } "
        "} "
        "/^  \\{[[:space:]]*$/ { "
        "  if (depth==1) { "
        "    in_obj=1; id=\"-\"; act=\"0\"; lc=\"-\"; tr=\"-\"; "
        "    cols=\"-\"; rows=\"-\"; pw=\"-\"; ph=\"-\"; tty=\"-\" "
        "  } next "
        "} "
        "/^  \\},?[[:space:]]*$/ { "
        "  if (in_obj && depth==0) { "
        "    printf \"%s %s %s %s %s %s %s %s %s\\n\", "
        "      id, act, lc, tr, cols, rows, pw, ph, tty "
        "  } "
        "  if (depth==0) in_obj=0; next "
        "} "
        "in_obj { "
        "  if      ($0 ~ /^    \"pane_id\":/)         { match($0,/[0-9]+/); id   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"is_active\":/)       { act  = ($0 ~ /true/) ? \"1\" : \"0\" } "
        "  else if ($0 ~ /^    \"left_col\":/)        { match($0,/[0-9]+/); lc   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"top_row\":/)         { match($0,/[0-9]+/); tr   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^      \"cols\":/)          { match($0,/[0-9]+/); cols = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^      \"rows\":/)          { match($0,/[0-9]+/); rows = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^      \"pixel_width\":/)   { match($0,/[0-9]+/); pw   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^      \"pixel_height\":/)  { match($0,/[0-9]+/); ph   = substr($0,RSTART,RLENGTH) } "
        "  else if ($0 ~ /^    \"tty_name\":/) { "
        "    s = $0; sub(/^[^\"]*\"tty_name\":[[:space:]]*\"/, \"\", s); "
        "    sub(/\",?[[:space:]]*$/, \"\", s); tty = s "
        "  } "
        "}"
        "'"))

    ;; Each pane record: (id active left top cols rows pixel-w pixel-h tty)
    ;; id/active/tty as strings; coords/dims as numbers (or #f).
    (define (list-panes-raw)
      (let* ((cmd (string-append
                    path-prefix
                    "wezterm cli list --format json 2>/dev/null | "
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
                                      (string->number (list-ref parts 2))
                                      (string->number (list-ref parts 3))
                                      (string->number (list-ref parts 4))
                                      (string->number (list-ref parts 5))
                                      (string->number (list-ref parts 6))
                                      (string->number (list-ref parts 7))
                                      (list-ref parts 8))
                                acc)))))))))

    (define (pane-id p)     (list-ref p 0))
    (define (pane-act p)    (list-ref p 1))
    (define (pane-left p)   (list-ref p 2))
    (define (pane-top p)    (list-ref p 3))
    (define (pane-cols p)   (list-ref p 4))
    (define (pane-rows p)   (list-ref p 5))
    (define (pane-pw p)     (list-ref p 6))
    (define (pane-ph p)     (list-ref p 7))
    (define (pane-tty p)    (list-ref p 8))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; The active pane is the one with is_active = true. Pane IDs are
    ;; stable integers per pane (sparse — killed panes leave gaps).
    ;; tty_name is `/dev/ttysNNN` directly — feed it to the legacy
    ;; tty-foreground-command helper to descend into a mux running
    ;; inside this WezTerm pane.

    (define (focused-pane)
      (find (lambda (p) (string=? (pane-act p) "1"))
                 (list-panes-raw)))

    (define (focused-pane-id)
      (let ((p (focused-pane)))
        (and p (pane-id p))))

    (define (detect-fg-command)
      (let ((p (focused-pane)))
        (and p
             (let ((t (pane-tty p)))
               (and t (not (string=? t "-")) (tty-foreground-command t))))))

    ;; ─── Op primitives ──────────────────────────────────────────────

    (define (focus-pane-left)  (wezterm-cli "activate-pane-direction Left"))
    (define (focus-pane-right) (wezterm-cli "activate-pane-direction Right"))
    (define (focus-pane-up)    (wezterm-cli "activate-pane-direction Up"))
    (define (focus-pane-down)  (wezterm-cli "activate-pane-direction Down"))

    ;; split-pane direction-flag mapping: WezTerm names the *result-side*
    ;; the new pane appears on, which matches the façade's direction
    ;; convention (split-pane-left → new pane on the left of the
    ;; current). Same naming axis as iTerm/tmux/zellij.
    (define (split-pane-left)  (wezterm-cli "split-pane --left"))
    (define (split-pane-right) (wezterm-cli "split-pane --right"))
    (define (split-pane-up)    (wezterm-cli "split-pane --top"))
    (define (split-pane-down)  (wezterm-cli "split-pane --bottom"))

    ;; toggle-pane-zoom: `wezterm cli zoom-pane --toggle` is a stateless
    ;; toggle — ADR-0007's required semantics. Added to the WezTerm CLI
    ;; some time after the 22-month-stale recovery notes, so it
    ;; supersedes the original keystroke-proxy plan.
    (define (toggle-pane-zoom) (wezterm-cli "zoom-pane --toggle"))

    ;; ─── Digit-jump chip rendering ──────────────────────────────────
    ;;
    ;; The chip canvas is the WezTerm pane subview (AXScrollArea, by
    ;; convention parallel to iTerm); the per-pane rect is derived from
    ;; JSON cell coords + the host frame's cell-pixel ratio. WezTerm's
    ;; JSON exposes pixel_width / pixel_height per pane directly, so the
    ;; ratio comes from any pane (we use the focused one). Falls back to
    ;; "no chips" when AX returns no scroll-areas or no panes are
    ;; parseable; digits still dispatch via the hidden key-range below.

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define (take-list xs n)
      (let loop ((xs xs) (n n) (acc '()))
        (cond
          ((or (null? xs) (<= n 0)) (reverse acc))
          (else (loop (cdr xs) (- n 1) (cons (car xs) acc))))))

    ;; Take the focused-pane AX frame as the per-cell origin / size
    ;; reference. WezTerm's JSON gives this pane's pixel dims +
    ;; cell dims; their ratio is the cell-pixel ratio for the host.
    ;; The other panes' rects are computed by walking JSON
    ;; (left_col, top_row, cols, rows) relative to the host window's
    ;; top-left, which is `focused_ax.x - focused.left_col * cell_w`,
    ;; etc.
    (define (host-frame)
      (let ((scrolls (ax-find-elements
                       "com.github.wez.wezterm" "AXScrollArea")))
        (and (pair? scrolls) (car scrolls))))

    ;; Per-pane chip entry shape matches `ax-find-elements` rows so
    ;; ax-target-hints consumes it unchanged. `handle` is #f — the
    ;; action invokes wezterm cli activate-pane --pane-id, not AX
    ;; focus.
    (define (chip-entries panes focused host)
      (let ((hx (cdr (assoc 'x host)))
            (hy (cdr (assoc 'y host)))
            (fl (pane-left focused))
            (ft (pane-top focused))
            (fc (pane-cols focused))
            (fr (pane-rows focused))
            (fpw (pane-pw focused))
            (fph (pane-ph focused)))
        (and fc fr fpw fph (> fc 0) (> fr 0)
             (let* ((cell-w   (quotient fpw fc))
                    (cell-h   (quotient fph fr))
                    ;; Window content origin: focused-pane AX frame
                    ;; minus its cell offset within the window.
                    (origin-x (- hx (* fl cell-w)))
                    (origin-y (- hy (* ft cell-h)))
                    (labels   (take-list digit-labels (length panes))))
               (let loop ((ps panes) (ls labels) (acc '()))
                 (cond
                   ((or (null? ps) (null? ls)) (reverse acc))
                   (else
                     (let* ((p  (car ps))
                            (pl (pane-left p))
                            (pt (pane-top p))
                            (pc (pane-cols p))
                            (pr (pane-rows p)))
                       (cond
                         ((and pl pt pc pr)
                          (let* ((x (+ origin-x (* pl cell-w)))
                                 (y (+ origin-y (* pt cell-h)))
                                 (w (* pc cell-w))
                                 (h (* pr cell-h))
                                 (entry (list (cons 'handle #f)
                                              (cons 'x x) (cons 'y y)
                                              (cons 'w w) (cons 'h h))))
                            (loop (cdr ps) (cdr ls)
                                  (cons (cons (car ls) entry) acc))))
                         (else (loop (cdr ps) ls acc)))))))))))

    ;; Snapshot taken at mode-enter so the digit-action closures don't
    ;; reissue the JSON query / awk parse at keystroke time. Same
    ;; pattern as tmux / zellij.
    (define *current-panes* '())
    (define (set-current-panes! ps) (set! *current-panes* ps))

    (define (focus-by-digit d)
      (let ((idx (string->number d))
            (panes *current-panes*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (p (and (< zero-based (length panes))
                         (list-ref panes zero-based))))
            (when p
              (wezterm-cli
                (string-append "activate-pane --pane-id " (pane-id p))))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'wezterm-pane-digit
        'on-enter
        (lambda ()
          (let* ((panes (list-panes-raw))
                 (focus (find (lambda (p) (string=? (pane-act p) "1"))
                                   panes))
                 (host  (host-frame)))
            (set-current-panes! panes)
            (cond
              ((and host focus (pair? panes))
               (let ((entries (chip-entries panes focus host)))
                 (cond
                   ((and entries (pair? entries))
                    (let ((hints (ax-target-hints
                                   entries (current-chip-theme 'normal))))
                      (hints-show hints)))
                   (else #f))))
              (else
                ;; AX didn't find a host frame, or no focused pane, or
                ;; no panes at all — skip hints-show. Digits still
                ;; dispatch via the range below.
                #f))))
        'on-leave (lambda () (hints-hide))
        (digit-range)))

    (define (focus-pane-by-digit)
      (enter-mode! 'wezterm-pane-digit))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — WezTerm has no provisioning step
    ;; in v1 (the move-pane gap is honest, not configurable). If a
    ;; future WezTerm release adds a directional swap action, this
    ;; flips to a real probe + configure-entry.

    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'wezterm "WezTerm" 'host "com.github.wez.wezterm"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        ;; move-pane-{left,right,up,down}: #f. No WezTerm primitive
        ;; implements directional pane swap (see module-level notes).
        #f #f #f #f
        focus-pane-by-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode. Safe to call more
    ;; than once: register-backend! is last-write-wins on backend
    ;; symbol; register-tree! replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!))))
