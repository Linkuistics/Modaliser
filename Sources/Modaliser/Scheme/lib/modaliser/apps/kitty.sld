;; (modaliser apps kitty) — Kitty host backend behind the
;; (modaliser terminal) façade. Implements 13/14 pane ops via the
;; `kitty @` remote-control IPC, plus detection and digit-jump chip
;; rendering.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser apps kitty) kitty:))
;;   (kitty:register!)
;;
;; ─── Op surface (13/14) ────────────────────────────────────────────
;;
;; Native via `kitty @`:
;;   - focus-pane-{left,right,up,down}  → focus-window --match=neighbor:…
;;   - split-pane-{down,right}          → launch --location={hsplit,vsplit}
;;   - split-pane-{left,up}             → launch + action move_window {left,up}
;;   - move-pane-{left,right,up,down}   → action move_window {left,right,up,down}
;;   - focus-pane-by-digit              → ls + focus-window --match=id:N
;;
;; Unsupported (#f, by design):
;;   - toggle-pane-zoom (Kitty has no native single-pane zoom)
;;
;; ─── Remote-control prerequisites ──────────────────────────────────
;;
;; `kitty @` needs three things in kitty.conf:
;;
;;   1. `allow_remote_control yes` — without it, the IPC is refused
;;      outright.
;;   2. `listen_on unix:/tmp/kitty-modaliser` — without it, `kitty @`
;;      from *outside* a kitty terminal has no socket to connect to.
;;      (The recovery notes used `--listen-on=` at launch for probing;
;;      this leaf bakes the same idea into the user's config so daily
;;      use works.) The path is fixed so configure-entry and the
;;      backend agree without parameter plumbing.
;;   3. `enabled_layouts splits,…` — without `splits` listed, kitty's
;;      `launch --location=vsplit` silently falls back to the active
;;      layout's behaviour. The directional split surface
;;      requires the splits layout.
;;
;; configure-entry provisions all three idempotently, backing up the
;; user's existing kitty.conf first.
;;
;; ─── Chip rendering ────────────────────────────────────────────────
;;
;; Chips are `(modaliser hints)` overlay windows (CONTEXT "Chip").
;; Kitty's `ls` JSON gives per-pane `lines`/`columns` and a `neighbors`
;; topology but no absolute cell offsets, so chip rects are derived in
;; three preferred-order paths:
;;
;;   1. **AX subviews.** If `ax-find-elements` on kitty.app returns one
;;      AXScrollArea per pane, use those rects directly — pixel-exact
;;      and font-free. Best case.
;;   2. **Topology BFS + cell-pixel ratio.** If AX returns a single
;;      host-window frame, walk `neighbors` to assign each pane a cell
;;      offset; derive cell-pixel ratio from host_frame / total_grid;
;;      compose per-pane rects.
;;   3. **No chips.** If AX returns nothing, skip hints-show; digits
;;      still dispatch via the hidden key-range below. Matches the
;;      wezterm fallback.
;;
;; The BFS is best-effort: complex nested layouts may leave a pane
;; unplaced; those panes are dropped from the chip set (the digit
;; range still maps them by enumeration order). Within ~1 cell-width
;; placement accuracy is the [[feedback_chips_are_overlays]] bar.

(define-library (modaliser apps kitty)
  (export register!
          backend
          configure-entry
          kitty-configured?)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser util)
          (modaliser shell)
          (modaliser dialogs)
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser theming)
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where kitty's `kitten` symlink
    ;; lives). Python3 sits at /usr/bin (macOS CLT), so it's always on
    ;; PATH; we still prepend the tool path so `kitty` resolves.
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; Fixed socket path. configure-entry writes the matching
    ;; `listen_on` directive into kitty.conf so this and the user's
    ;; running kitty instance agree without parameter plumbing.
    (define kitty-socket "unix:/tmp/kitty-modaliser")

    (define (kitty-cli args)
      (run-shell
        (string-append
          path-prefix
          "kitty @ --to=" kitty-socket " " args " 2>/dev/null")))

    ;; ─── Pane-list parser ───────────────────────────────────────────
    ;;
    ;; Kitty's `ls` JSON is deeply nested (os_windows → tabs → windows
    ;; → neighbors arrays), so the per-backend awk pattern other modules
    ;; use would be a real JSON state machine. macOS ships
    ;; /usr/bin/python3 via the Command Line Tools, so we use it here —
    ;; a deliberate single-backend deviation motivated by data shape.
    ;;
    ;; Emits one tab-separated row per kitty window (= pane in
    ;; CONTEXT.md terms) within the currently-active OS window's
    ;; currently-active tab. `ls` returns the full kitty UI tree
    ;; including background tabs and other OS-windows; flattening
    ;; would place panes from different tabs into one grid, which
    ;; the position-propagation pass then collides. Restricting to
    ;; the active tab gives chip / detection results matching the
    ;; user's screen.
    ;;
    ;;   <id>\t<is_focused 0|1>\t<lines>\t<columns>\t
    ;;   <left_ids>\t<right_ids>\t<top_ids>\t<bottom_ids>\t<fg_cmd>
    ;;
    ;; *_ids are comma-joined integer lists or "-" when empty.
    ;; The "focused" column reflects `is_active` (the always-populated
    ;; "this is the chosen pane in the active tab" flag) rather than
    ;; `is_focused` (which is true only while kitty.app is itself
    ;; frontmost). Modaliser dispatches to this backend only when
    ;; kitty.app is frontmost, so the two agree at dispatch time;
    ;; using `is_active` also makes tests / probes invoking the
    ;; parser from another frontmost app return sensible answers.
    ;; fg_cmd is the LAST foreground_processes entry's cmdline[0]
    ;; (the innermost descendant — per kitty 0.47.0 notes/kitty.md, the
    ;; first element is the shell and the last is the visible
    ;; foreground tool). Empty → "-". Tabs in the field are stripped
    ;; (kitty cmdlines don't normally contain them, but defensive).
    (define parse-script
      (string-append
        "/usr/bin/python3 - <<'PYEOF' 2>/dev/null\n"
        "import json, sys\n"
        "raw = sys.stdin.read()\n"
        "if not raw.strip():\n"
        "    sys.exit(0)\n"
        "try:\n"
        "    data = json.loads(raw)\n"
        "except Exception:\n"
        "    sys.exit(0)\n"
        "def pick_active(items):\n"
        "    for it in items:\n"
        "        if it.get(\"is_active\"):\n"
        "            return it\n"
        "    return items[0] if items else None\n"
        "def join_ids(nb, key):\n"
        "    xs = nb.get(key, [])\n"
        "    return \",\".join(str(x) for x in xs) if xs else \"-\"\n"
        "def fg_cmd(w):\n"
        "    fg = w.get(\"foreground_processes\", [])\n"
        "    if not fg:\n"
        "        return \"-\"\n"
        "    last = fg[-1].get(\"cmdline\", [])\n"
        "    if not last:\n"
        "        return \"-\"\n"
        "    return str(last[0]).replace(\"\\t\", \" \")\n"
        "ow = pick_active(data)\n"
        "if ow is None:\n"
        "    sys.exit(0)\n"
        "tab = pick_active(ow.get(\"tabs\", []))\n"
        "if tab is None:\n"
        "    sys.exit(0)\n"
        "for w in tab.get(\"windows\", []):\n"
        "    wid     = w.get(\"id\", -1)\n"
        "    focused = 1 if w.get(\"is_active\") else 0\n"
        "    lines   = w.get(\"lines\", 0)\n"
        "    cols    = w.get(\"columns\", 0)\n"
        "    nb      = w.get(\"neighbors\", {})\n"
        "    row = [str(wid), str(focused), str(lines), str(cols),\n"
        "           join_ids(nb, \"left\"), join_ids(nb, \"right\"),\n"
        "           join_ids(nb, \"top\"),  join_ids(nb, \"bottom\"),\n"
        "           fg_cmd(w)]\n"
        "    print(\"\\t\".join(row))\n"
        "PYEOF\n"))

    ;; Each pane record: (id focused lines cols lefts rights tops bottoms fg)
    ;; id/lefts/.../fg as strings; focused/lines/cols as numbers (or #f).
    (define (list-panes-raw)
      (let* ((cmd (string-append
                    path-prefix
                    "kitty @ --to=" kitty-socket " ls 2>/dev/null | "
                    parse-script))
             (out (run-shell cmd)))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let* ((line (string-trim (car lines)))
                     (parts (string-split line "\t")))
                (if (or (string=? line "") (< (length parts) 9))
                    (loop (cdr lines) acc)
                    (loop (cdr lines)
                          (cons (list (list-ref parts 0)
                                      (string->number (list-ref parts 1))
                                      (string->number (list-ref parts 2))
                                      (string->number (list-ref parts 3))
                                      (list-ref parts 4)
                                      (list-ref parts 5)
                                      (list-ref parts 6)
                                      (list-ref parts 7)
                                      (list-ref parts 8))
                                acc)))))))))

    (define (pane-id p)       (list-ref p 0))
    (define (pane-focused p)  (list-ref p 1))
    (define (pane-lines p)    (list-ref p 2))
    (define (pane-cols p)     (list-ref p 3))
    (define (pane-lefts p)    (list-ref p 4))
    (define (pane-rights p)   (list-ref p 5))
    (define (pane-tops p)     (list-ref p 6))
    (define (pane-bottoms p)  (list-ref p 7))
    (define (pane-fg p)       (list-ref p 8))

    ;; Comma-joined id string → list of id strings. "-" → '().
    (define (split-ids s)
      (cond
        ((or (string=? s "") (string=? s "-")) '())
        (else (string-split s ","))))

    ;; ─── Detection ──────────────────────────────────────────────────

    (define (focused-pane)
      (find (lambda (p)
                   (let ((f (pane-focused p)))
                     (and f (= f 1))))
                 (list-panes-raw)))

    (define (focused-pane-id)
      (let ((p (focused-pane)))
        (and p (pane-id p))))

    (define (detect-fg-command)
      (let ((p (focused-pane)))
        (and p
             (let ((c (pane-fg p)))
               (and c (not (string=? c "-")) c)))))

    ;; ─── Op primitives ──────────────────────────────────────────────

    (define (focus-pane-left)  (kitty-cli "focus-window --match=neighbor:left"))
    (define (focus-pane-right) (kitty-cli "focus-window --match=neighbor:right"))
    (define (focus-pane-up)    (kitty-cli "focus-window --match=neighbor:top"))
    (define (focus-pane-down)  (kitty-cli "focus-window --match=neighbor:bottom"))

    ;; split-pane direction convention (façade): new pane appears on
    ;; the named side. Kitty's `launch --location` only exposes hsplit
    ;; (below) and vsplit (right); split-up and split-left compose
    ;; with a follow-up `move_window` on the just-created pane (which
    ;; `launch` focuses by default).
    (define (split-pane-down)  (kitty-cli "launch --location=hsplit"))
    (define (split-pane-right) (kitty-cli "launch --location=vsplit"))
    (define (split-pane-up)
      (kitty-cli "launch --location=hsplit")
      (kitty-cli "action move_window up"))
    (define (split-pane-left)
      (kitty-cli "launch --location=vsplit")
      (kitty-cli "action move_window left"))

    (define (move-pane-left)   (kitty-cli "action move_window left"))
    (define (move-pane-right)  (kitty-cli "action move_window right"))
    (define (move-pane-up)     (kitty-cli "action move_window up"))
    (define (move-pane-down)   (kitty-cli "action move_window down"))

    ;; ─── configure-entry ────────────────────────────────────────────
    ;;
    ;; Provisions kitty.conf with the three load-bearing directives
    ;; (allow_remote_control, listen_on, enabled_layouts including
    ;; splits). Backs up the user's existing file first — the BRIEF
    ;; notes that user's existing kitty.conf is a 98-line A/B-rendering
    ;; mirror of wezterm.lua and must not be silently mangled.
    ;;
    ;; The provision script is idempotent: a marker comment makes
    ;; re-runs skip work that's already been done. Reading the user's
    ;; kitty.conf in this many incremental passes is a deliberate
    ;; trade against the more elegant single-pass rewrite: each
    ;; directive's "add if missing, fix if wrong" logic is independent,
    ;; which keeps the diff small when only one is out of sync.

    (define kitty-conf-path "$HOME/.config/kitty/kitty.conf")
    (define kitty-conf-backup "$HOME/.config/kitty/kitty.conf.modaliser-backup")
    (define kitty-marker "# modaliser:configured")

    (define kitty-provision-script
      (string-append
        "set -e\n"
        "P=" kitty-conf-path "\n"
        "B=" kitty-conf-backup "\n"
        "mkdir -p \"$(dirname \"$P\")\"\n"
        ;; Initial backup only on the first run — preserve the
        ;; pre-Modaliser file forever; subsequent runs leave the
        ;; backup alone (so a user who wants to revert has the
        ;; original, not yesterday's already-modaliser-touched copy).
        "if [ ! -f \"$B\" ] && [ -f \"$P\" ]; then cp \"$P\" \"$B\"; fi\n"
        "touch \"$P\"\n"
        ;; allow_remote_control: ensure `yes`.
        "if grep -qE '^[[:space:]]*allow_remote_control[[:space:]]' \"$P\"; then\n"
        "  /usr/bin/sed -i.bak -E "
        "'s/^[[:space:]]*allow_remote_control[[:space:]].*/allow_remote_control yes/' \"$P\"\n"
        "  rm -f \"$P.bak\"\n"
        "else\n"
        "  printf '\\nallow_remote_control yes\\n' >> \"$P\"\n"
        "fi\n"
        ;; listen_on: ensure exact match.
        "if grep -qE '^[[:space:]]*listen_on[[:space:]]' \"$P\"; then\n"
        "  /usr/bin/sed -i.bak -E "
        "'s|^[[:space:]]*listen_on[[:space:]].*|listen_on " kitty-socket "|' \"$P\"\n"
        "  rm -f \"$P.bak\"\n"
        "else\n"
        "  printf 'listen_on " kitty-socket "\\n' >> \"$P\"\n"
        "fi\n"
        ;; enabled_layouts: ensure `splits` is present in the list.
        ;; If the directive exists and lacks splits, prepend `splits,`.
        ;; If absent, write `enabled_layouts splits,tall,stack` (kitty's
        ;; default set plus splits).
        "if grep -qE '^[[:space:]]*enabled_layouts[[:space:]]' \"$P\"; then\n"
        "  if ! grep -qE '^[[:space:]]*enabled_layouts[[:space:]].*\\bsplits\\b' \"$P\"; then\n"
        "    /usr/bin/sed -i.bak -E "
        "'s/^([[:space:]]*enabled_layouts[[:space:]]+)/\\1splits,/' \"$P\"\n"
        "    rm -f \"$P.bak\"\n"
        "  fi\n"
        "else\n"
        "  printf 'enabled_layouts splits,tall,stack\\n' >> \"$P\"\n"
        "fi\n"
        ;; Marker comment — emitted once, makes provisioning state
        ;; visible to a human reader of the conf file.
        "if ! grep -qF '" kitty-marker "' \"$P\"; then\n"
        "  printf '\\n" kitty-marker "\\n' >> \"$P\"\n"
        "fi\n"))

    ;; Probe: are all three directives present with the values we
    ;; need? Independent of whether kitty is running; the conf file
    ;; is the source of truth (kitty re-reads it on relaunch).
    (define (kitty-probe-configured?)
      (string=?
        (string-trim
          (run-shell
            (string-append
              "P=" kitty-conf-path "\n"
              "ok=yes\n"
              "[ -f \"$P\" ] || ok=no\n"
              "if [ \"$ok\" = yes ]; then\n"
              "  grep -qE '^[[:space:]]*allow_remote_control[[:space:]]+yes' \"$P\" || ok=no\n"
              "  grep -qE '^[[:space:]]*listen_on[[:space:]]+" kitty-socket "' \"$P\" || ok=no\n"
              "  grep -qE '^[[:space:]]*enabled_layouts[[:space:]].*\\bsplits\\b' \"$P\" || ok=no\n"
              "fi\n"
              "echo $ok")))
        "yes"))

    ;; Cached configured? flag — the overlay's 'hidden thunk reads
    ;; this on every render, so the probe must be cheap. 'unknown
    ;; forces a one-time lazy probe; iterm-style refresh after
    ;; provisioning so the entry vanishes without a Modaliser reload.
    (define *kitty-configured* 'unknown)

    (define (kitty-configured?)
      (when (eq? *kitty-configured* 'unknown)
        (set! *kitty-configured* (kitty-probe-configured?)))
      *kitty-configured*)

    (define (kitty-refresh-configured!)
      (set! *kitty-configured* (kitty-probe-configured?))
      *kitty-configured*)

    (define kitty-configure-dialog-message
      (string-append
        "Modaliser needs three settings in your kitty config to drive "
        "pane splits, moves and digit-jump:\n\n"
        "  - allow_remote_control yes   (enables `kitty @` IPC)\n"
        "  - listen_on " kitty-socket "\n"
        "       (the socket Modaliser talks to)\n"
        "  - enabled_layouts splits,…   (kitty's directional splits)\n\n"
        "Choosing Continue will:\n\n"
        "  - Back up your current ~/.config/kitty/kitty.conf to\n"
        "       kitty.conf.modaliser-backup (one-time, kept forever)\n"
        "  - Add or amend the three directives above\n"
        "  - Leave the rest of your config untouched\n\n"
        "You'll need to relaunch Kitty for the changes to take effect."))

    ;; Overlay action: confirm (async, ADR-0014 — the dialog fires through
    ;; the slim (modaliser dialogs) library so the Scheme thread stays free
    ;; while it's up), provision, re-probe. Idempotent — if kitty is already
    ;; configured (e.g. the key was pressed while the entry was hidden) it
    ;; just syncs the cache and returns, no dialog.
    (define (kitty-configure!)
      (if (kitty-probe-configured?)
        (kitty-refresh-configured!)
        (dialog-confirm kitty-configure-dialog-message
          (lambda (continue?)
            (when continue?
              (run-shell kitty-provision-script)
              (kitty-refresh-configured!)))
          'title "Configure Kitty" 'ok-label "Continue" 'icon "caution")))

    ;; A `(key …)` node bound to Ctrl+Shift+I (same key as iTerm's
    ;; configure-entry — they're mutually exclusive by frontmost app,
    ;; so the keybinding can be re-used). The 'hidden thunk lets the
    ;; entry vanish from the overlay once configured.
    (define (configure-entry)
      (cons (cons 'hidden kitty-configured?)
            (key "C-I" "Configure Kitty" kitty-configure!)))

    ;; ─── Digit-jump chip rendering ──────────────────────────────────

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    (define (take-list xs n)
      (let loop ((xs xs) (n n) (acc '()))
        (cond
          ((or (null? xs) (<= n 0)) (reverse acc))
          (else (loop (cdr xs) (- n 1) (cons (car xs) acc))))))

    ;; AX-rect path. If kitty.app exposes one AXScrollArea per pane,
    ;; the rects are pixel-exact already. Returns #f if the count
    ;; doesn't match the JSON pane count — that means AX is exposing
    ;; the host frame, not per-pane subviews; the BFS path takes over.
    (define (ax-rect-entries panes)
      (let ((rects (ax-find-elements
                     "net.kovidgoyal.kitty" "AXScrollArea")))
        (cond
          ((and (= (length rects) (length panes))
                (>= (length rects) 1)
                ;; Reject the degenerate single-pane case here too —
                ;; one rect could be either per-pane or host frame;
                ;; the BFS path is identical work for one pane and
                ;; serves as the unambiguous default.
                (> (length rects) 1))
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
          (else #f))))

    ;; Constraint-propagation positioning. Walks `neighbors` to assign
    ;; each pane a (col, row) cell offset.
    ;;
    ;; A pane's position is constrained by *all* its left and top
    ;; neighbors simultaneously: col = max over L of (L.col + L.cols);
    ;; row = max over T of (T.row + T.lines). With no L or T,
    ;; col = 0 / row = 0 (the top-left pane).
    ;;
    ;; The probe at implementation time revealed kitty's `neighbors`
    ;; is a relation, not a tree — a pane can list two right neighbors
    ;; that sit stacked vertically (one above the other). A pure BFS
    ;; from the top-left placing each neighbor at "parent's right edge"
    ;; would incorrectly collide them at the same row. The constraint-
    ;; propagation pass below places any pane whose L+T neighbors are
    ;; already placed; iterating until no progress means a pane's row
    ;; is decided by its top-neighbor's bottom edge, not by who walked
    ;; into it first.
    ;;
    ;; Panes whose neighbors can't all be placed (unusual under the
    ;; splits layout's orthogonal constraint) are dropped from the
    ;; result; their chips won't render and the digit range below
    ;; still dispatches by enumeration order.
    ;;
    ;; Returns an alist keyed by pane-id with values (col row), both
    ;; in cells.
    (define (bfs-positions panes)
      (define by-id (map (lambda (p) (cons (pane-id p) p)) panes))
      (define (lookup id) (let ((e (assoc id by-id))) (and e (cdr e))))

      (define (all-placed? ids placed)
        (let loop ((ids ids))
          (cond
            ((null? ids) #t)
            ((assoc (car ids) placed) (loop (cdr ids)))
            (else #f))))

      (define (max-edge ids placed edge-fn)
        ;; `edge-fn` takes (placed-pos-list neighbor-pane) and returns
        ;; the cell index at that neighbor's far edge.
        (let loop ((ids ids) (best 0))
          (cond
            ((null? ids) best)
            (else
              (let* ((id (car ids))
                     (pos (cdr (assoc id placed)))
                     (p   (lookup id))
                     (val (and p (edge-fn pos p))))
                (loop (cdr ids)
                      (if (and val (> val best)) val best)))))))

      (define (compute-pos p placed)
        (let* ((lefts (split-ids (pane-lefts p)))
               (tops  (split-ids (pane-tops p)))
               (col (if (null? lefts) 0
                        (max-edge lefts placed
                                  (lambda (pos lp)
                                    (and (pane-cols lp)
                                         (+ (list-ref pos 0) (pane-cols lp)))))))
               (row (if (null? tops) 0
                        (max-edge tops placed
                                  (lambda (pos tp)
                                    (and (pane-lines tp)
                                         (+ (list-ref pos 1) (pane-lines tp))))))))
          (list col row)))

      ;; One pass through `pending`: place any pane whose all L+T
      ;; neighbors are already in `placed`. Returns the updated
      ;; placed list and the list of panes that still couldn't be
      ;; placed this pass.
      (define (place-pass pending placed)
        (let loop ((ps pending) (placed1 placed) (still '()))
          (cond
            ((null? ps) (cons placed1 (reverse still)))
            (else
              (let* ((p (car ps))
                     (lefts (split-ids (pane-lefts p)))
                     (tops  (split-ids (pane-tops p))))
                (cond
                  ((and (all-placed? lefts placed1)
                        (all-placed? tops  placed1))
                   (loop (cdr ps)
                         (cons (cons (pane-id p) (compute-pos p placed1))
                               placed1)
                         still))
                  (else
                    (loop (cdr ps) placed1 (cons p still)))))))))

      (let outer ((placed '()) (pending panes))
        (cond
          ((null? pending) (reverse placed))
          (else
            (let* ((result (place-pass pending placed))
                   (placed1 (car result))
                   (still   (cdr result)))
              (cond
                ;; No progress this pass → leftover panes are
                ;; unreachable from the topology root. Bail with what
                ;; we have.
                ((= (length still) (length pending)) (reverse placed1))
                (else (outer placed1 still))))))))

    (define (host-frame-pixel)
      (let ((rects (ax-find-elements
                     "net.kovidgoyal.kitty" "AXScrollArea")))
        (and (pair? rects) (car rects))))

    ;; Compute total grid cell extent from BFS placements + per-pane
    ;; (cols, lines). Returns (total_cols total_rows) or #f if either
    ;; can't be derived.
    (define (grid-extent panes positions)
      (let loop ((ps panes) (max-c 0) (max-r 0))
        (cond
          ((null? ps)
           (and (> max-c 0) (> max-r 0) (list max-c max-r)))
          (else
            (let* ((p (car ps))
                   (entry (assoc (pane-id p) positions))
                   (cols (pane-cols p))
                   (rows (pane-lines p)))
              (cond
                ((and entry cols rows)
                 (let* ((pos (cdr entry))
                        (col (list-ref pos 0))
                        (row (list-ref pos 1))
                        (end-c (+ col cols))
                        (end-r (+ row rows)))
                   (loop (cdr ps)
                         (if (> end-c max-c) end-c max-c)
                         (if (> end-r max-r) end-r max-r))))
                (else (loop (cdr ps) max-c max-r))))))))

    (define (bfs-rect-entries panes host)
      (let* ((positions (bfs-positions panes))
             (extent    (grid-extent panes positions)))
        (and (pair? positions) extent
             (let ((hx (cdr (assoc 'x host)))
                   (hy (cdr (assoc 'y host)))
                   (hw (cdr (assoc 'w host)))
                   (hh (cdr (assoc 'h host)))
                   (grid-w (car extent))
                   (grid-h (cadr extent)))
               (and (> grid-w 0) (> grid-h 0)
                    (let ((labels (take-list digit-labels (length panes))))
                      (let loop ((ps panes) (ls labels) (acc '()))
                        (cond
                          ((or (null? ps) (null? ls)) (reverse acc))
                          (else
                            (let* ((p (car ps))
                                   (id (pane-id p))
                                   (entry (assoc id positions)))
                              (cond
                                ((and entry (pane-cols p) (pane-lines p))
                                 (let* ((pos (cdr entry))
                                        (col (list-ref pos 0))
                                        (row (list-ref pos 1))
                                        (x (+ hx (quotient (* col hw) grid-w)))
                                        (y (+ hy (quotient (* row hh) grid-h)))
                                        (w (quotient (* (pane-cols p) hw) grid-w))
                                        (h (quotient (* (pane-lines p) hh) grid-h))
                                        (e (list (cons 'handle #f)
                                                 (cons 'x x) (cons 'y y)
                                                 (cons 'w w) (cons 'h h))))
                                   (loop (cdr ps) (cdr ls)
                                         (cons (cons (car ls) e) acc))))
                                (else (loop (cdr ps) ls acc)))))))))))))

    ;; Snapshot at mode-enter so digit-action closures don't reissue
    ;; the JSON query at keystroke time. Same pattern as tmux / zellij
    ;; / wezterm.
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
              (kitty-cli
                (string-append "focus-window --match=id:" (pane-id p))))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'kitty-pane-digit
        'on-enter
        (lambda ()
          (let ((panes (list-panes-raw)))
            (set-current-panes! panes)
            (cond
              ((not (pair? panes)) #f)
              (else
                (let ((entries
                        (or (ax-rect-entries panes)
                            (let ((host (host-frame-pixel)))
                              (and host (bfs-rect-entries panes host))))))
                  (cond
                    ((and entries (pair? entries))
                     (let ((hints (ax-target-hints
                                    entries (current-chip-theme 'normal))))
                       (hints-show hints)))
                    (else
                      ;; No AX, no BFS-derivable rects, or empty pane
                      ;; list — skip hints-show. Digits still dispatch
                      ;; via the hidden range below.
                      #f)))))))
        'on-leave (lambda () (hints-hide))
        (digit-range)))


    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; toggle-pane-zoom field is #f — Kitty has no native single-pane
    ;; zoom. `(supports-zoom?)` reports #f accordingly.

    (define backend
      (make-terminal-backend
        'kitty "Kitty" 'host "net.kovidgoyal.kitty"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        'kitty-pane-digit
        ;; toggle-pane-zoom: #f — Kitty has no native single-
        ;; pane zoom; (supports-zoom?) is the only capability predicate
        ;; that flips to #f for a splitting backend in v1.
        #f
        kitty-configured?))

    (define (register!)
      (register-backend! backend)
      (pane-digit-register!))))
