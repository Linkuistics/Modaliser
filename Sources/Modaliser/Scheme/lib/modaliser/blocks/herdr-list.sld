;; (modaliser blocks herdr-list) — one block constructor for herdr's three
;; live lists (panes / tabs / workspaces). herdr's socket-API CLI hands us
;; the id, focused flag and label of every pane/tab/workspace directly as
;; JSON, so — unlike the iTerm blocks — there is NO AX walk, no UUID
;; correlation and no empty-title fallback. The three lists differ only in
;; which `herdr <x> list` to run and how to read each row, so a single
;; `kind`-parameterised block covers all three.
;;
;; (make-herdr-list-block 'kind 'panes|'tabs|'workspaces . opts) → block-spec
;;
;; The block exposes (herdr-list-current-targets) → ((label . id) …) so the
;; parent group can build a hidden (key-range "1.." …) that dispatches each
;; digit to the matching id. The focus ACTION lives in (modaliser muxes
;; herdr) — `agent focus <pane_id>` / `tab focus <id>` / `workspace focus
;; <id>` — not here, keeping this module UI-only (it never shells a mutating
;; op).
;;
;; ── Single-render invariant ──
;; State (current-targets / current-data) is module-level, one cell shared by
;; all three kinds. That is safe because the herdr variant tree renders at
;; most ONE herdr list per overlay frame: panes at the top level, tabs under
;; `open "t"`, workspaces under `open "w"` — never two at once. Each render
;; overwrites the cell with the visible list, and the digit key-range reads
;; it at key-press time, so it always sees the list on screen. (The iTerm
;; blocks use a module-state cell per list; herdr collapses to one because
;; the three never co-render.)
;;
;; ── Pane chips (panes kind, 'chips? #t) ──
;; With 'chips? #t the panes block also paints digit chips over the on-screen
;; herdr panes (mirroring iterm-panes' paint-and-snapshot! / hints-hide). Rects
;; come from `herdr pane layout` — per-pane cell rects scaled by the focused
;; iTerm AXScrollArea pixel frame, tmux-style. Two subtleties:
;;   • AREA-RELATIVE. herdr paints a left sidebar, so layout.area.x ≥ 26; we
;;     subtract area.x/area.y before scaling so the sidebar offset doesn't
;;     shift every chip right.
;;   • SUBSET of rows. `pane layout` covers only the CURRENT tab's splits,
;;     while `pane list` (the row source) spans all tabs. So chips are keyed to
;;     the row labels by pane_id: a row whose pane is off-tab simply gets no
;;     chip. Digit-jump still focuses it by id (via `agent focus`); only the
;;     visible chip is absent.
;;   • REPLACE MODE ONLY is correct. host-frame takes the FIRST iTerm
;;     AXScrollArea; in replace mode herdr owns the sole one, so the frame is
;;     right. In augment mode (herdr + other iTerm splits) that first area may
;;     be the wrong split, so chips can land on the wrong pixels — a documented
;;     v1 limitation (docs/reference/terminal-detection.md). hjkl focus and
;;     digit-jump are unaffected; the proper fix (a focused-iTerm-session-frame
;;     primitive) is the optional deferred leaf.

(define-library (modaliser blocks herdr-list)
  (export make-herdr-list-block
          herdr-list-current-targets
          herdr-list-current-labels
          herdr-list-focused-index
          herdr-list-refresh!
          ;; Pure JSON → (targets . rows) extractor, exported for unit tests
          ;; (fed a parsed `herdr <x> list` fixture, no live herdr needed).
          herdr-list-extract
          ;; Pure chip-rect synthesis (targets + parsed `pane layout` + host
          ;; frame → labelled chip entries), exported for unit tests.
          herdr-chip-entries
          default-herdr-labels)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser json)
          (only (modaliser terminal) modaliser-tool-path)
          ;; Chip overlay: AX host frame + hint painting + resolved chip theme.
          ;; Same set the iTerm panes block leans on; all (modaliser …)
          ;; libraries, so the portable-surface contract holds (nothing from
          ;; the host LispKit tree crosses into lib/modaliser).
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser theming)
          (modaliser overlay-assets))
  (begin

    (define default-herdr-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Per-render state — one shared cell (see the single-render invariant
    ;; above). current-targets drives digit dispatch; current-data is the
    ;; rendered rows.
    (define current-targets '())   ;; ((label . id) …)
    (define current-data '())      ;; row alists: ((label title detail focused) …)

    (define (herdr-list-current-targets) current-targets)
    (define (herdr-list-current-labels) (map car current-targets))

    ;; Row index of the focused entry among the rendered rows, for the
    ;; selection cursor's initial position (list-cursor-initial-focus-k25).
    ;; #f when none is focused (→ cursor seeds row 0).
    (define (herdr-list-focused-index)
      (let loop ((rows current-data) (i 0))
        (cond
          ((null? rows) #f)
          ((let ((f (assoc 'focused (car rows)))) (and f (cdr f))) i)
          (else (loop (cdr rows) (+ i 1))))))

    ;; GUI-launched Modaliser inherits a stripped PATH that omits
    ;; /opt/homebrew/bin (where herdr lives) — same prefix the herdr backend
    ;; and the tmux/zellij helpers use.
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; Run `herdr <subcmd>`, parse stdout as JSON → alist/vector tree, or #f
    ;; on empty/non-JSON output. The guard keeps a truncated line from
    ;; raising through a render pass (herdr output is reliably JSON, even
    ;; errors, but a render must never break).
    (define (herdr-list-json subcmd)
      (let ((out (string-trim
                   (run-shell
                     (string-append path-prefix "herdr " subcmd " 2>/dev/null")))))
        (if (string=? out "")
            #f
            (guard (e (#t #f)) (json-parse out)))))

    ;; Per-kind spec: (cli-subcommand result-array-key id-key title-key).
    ;; The result envelope is {"result":{"<array-key>":[ … ]}} for every
    ;; list command; each element carries an id, a `focused` bool and a
    ;; human label. Panes have no `label`, so their title falls back to the
    ;; agent name then the pane id.
    (define (kind-spec kind)
      (cond
        ((eq? kind 'panes)
         (list "pane list" "panes" "pane_id" #f))
        ((eq? kind 'tabs)
         (list "tab list" "tabs" "tab_id" "label"))
        ((eq? kind 'workspaces)
         (list "workspace list" "workspaces" "workspace_id" "label"))
        (else (error "herdr-list: unknown kind" kind))))

    ;; Title for one row. Tabs/workspaces carry a `label`; panes don't, so a
    ;; pane reads its agent name (e.g. "claude"), falling back to the pane id.
    (define (row-title kind item id title-key)
      (cond
        (title-key
         (let ((v (json-ref item title-key)))
           (if (string? v) v id)))
        (else
         (let ((agent (json-ref item "agent")))
           (if (string? agent) agent id)))))

    ;; Secondary dimmed text. Panes show their cwd; tabs/workspaces show
    ;; nothing (the label already identifies them).
    (define (row-detail kind item)
      (if (eq? kind 'panes)
          (let ((cwd (json-ref item "cwd"))) (if (string? cwd) cwd ""))
          ""))

    ;; Pure extractor: parsed `herdr <x> list` JSON + kind + labels →
    ;; (targets . rows). targets = ((label . id) …) for the first (length
    ;; labels) entries; rows = every entry as ((label title detail focused)).
    ;; An entry past the label supply still renders (blank key, no dispatch).
    ;; Exported so a fixture-fed test needs no live herdr.
    (define (herdr-list-extract kind labels parsed)
      (let* ((spec      (kind-spec kind))
             (array-key (list-ref spec 1))
             (id-key    (list-ref spec 2))
             (title-key (list-ref spec 3))
             (arr (and parsed
                       (json-ref (json-ref parsed "result") array-key)))
             (items (if (vector? arr) arr #())))
        (let loop ((k 0) (labs labels) (targets '()) (rows '()))
          (cond
            ((>= k (vector-length items))
             (cons (reverse targets) (reverse rows)))
            (else
             (let* ((item     (vector-ref items k))
                    (id       (json-ref item id-key))
                    (focused  (eq? (json-ref item "focused") #t))
                    (title    (row-title kind item (if (string? id) id "") title-key))
                    (detail   (row-detail kind item))
                    (has-lab  (pair? labs))
                    (label    (if has-lab (car labs) "")))
               (loop (+ k 1)
                     (if has-lab (cdr labs) labs)
                     (if (and has-lab (string? id))
                         (cons (cons label id) targets)
                         targets)
                     (cons (list (cons 'label label)
                                 (cons 'title title)
                                 (cons 'detail detail)
                                 (cons 'focused focused))
                           rows))))))))

    ;; Query herdr, extract, store into the shared cell. Returns targets.
    (define (snapshot! kind labels)
      (let* ((spec   (kind-spec kind))
             (parsed (herdr-list-json (list-ref spec 0)))
             (pair   (herdr-list-extract kind labels parsed)))
        (set! current-targets (car pair))
        (set! current-data    (cdr pair))
        current-targets))

    ;; On-demand refresh for the digit key-range: a leader-then-digit press
    ;; faster than the overlay delay can fire before the on-render snapshot
    ;; ran, so the dispatcher re-snapshots the right kind and looks again.
    (define (herdr-list-refresh! kind)
      (snapshot! kind default-herdr-labels)
      current-targets)

    ;; ─── Pane chips ─────────────────────────────────────────────────
    ;;
    ;; Rects come from `herdr pane layout`; see the module header for the
    ;; area-relative / subset-of-rows / replace-mode-only notes. The pure
    ;; synthesis (herdr-chip-entries) is exported so a fixture-fed test needs
    ;; no live herdr or AX.

    ;; (result.layout.area) → (x y width height), or #f. width/height must be
    ;; positive (they divide) or the layout is unusable.
    (define (herdr-layout-area layout)
      (let ((a (json-ref (json-ref (json-ref layout "result") "layout") "area")))
        (and a
             (let ((x (json-ref a "x")) (y (json-ref a "y"))
                   (w (json-ref a "width")) (h (json-ref a "height")))
               (and (number? x) (number? y) (number? w) (number? h)
                    (> w 0) (> h 0)
                    (list x y w h))))))

    ;; (result.layout.panes) → ((pane_id . (x y width height)) …). Panes
    ;; without a well-formed rect are dropped rather than raising.
    (define (herdr-layout-rects layout)
      (let ((panes (json-ref (json-ref (json-ref layout "result") "layout") "panes")))
        (if (vector? panes)
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length panes))
                  (reverse acc)
                  (let* ((p   (vector-ref panes k))
                         (pid (json-ref p "pane_id"))
                         (r   (json-ref p "rect"))
                         (rx  (and r (json-ref r "x")))
                         (ry  (and r (json-ref r "y")))
                         (rw  (and r (json-ref r "width")))
                         (rh  (and r (json-ref r "height"))))
                    (loop (+ k 1)
                          (if (and (string? pid)
                                   (number? rx) (number? ry)
                                   (number? rw) (number? rh))
                              (cons (cons pid (list rx ry rw rh)) acc)
                              acc)))))
            '())))

    ;; (herdr-chip-entries targets layout host) → labelled chip entries ready
    ;; for ax-target-hints. targets = ((label . pane_id) …) from the row
    ;; snapshot; layout = parsed `pane layout`; host = the iTerm AXScrollArea
    ;; frame alist ((x)(y)(w)(h)). Each entry is (label . ((handle . #f)
    ;; (x)(y)(w)(h))) — same shape ax-find-elements rows have, so
    ;; ax-target-hints consumes it unchanged (it places the chip inset from the
    ;; entry's top-left and sizes it from the theme; w/h ride along for parity).
    ;; Cell→pixel scale is area-relative: subtract area.x/area.y before scaling
    ;; so herdr's left sidebar doesn't shift chips. quotient (multiply-then-
    ;; divide) keeps integer precision, exactly as tmux's chip-entries does.
    ;; A target whose pane is absent from this (current-tab) layout is skipped.
    (define (herdr-chip-entries targets layout host)
      (let ((area (and layout (herdr-layout-area layout))))
        (if (not (and area host))
            '()
            (let ((ax (list-ref area 0)) (ay (list-ref area 1))
                  (aw (list-ref area 2)) (ah (list-ref area 3))
                  (hx (cdr (assoc 'x host))) (hy (cdr (assoc 'y host)))
                  (hw (cdr (assoc 'w host))) (hh (cdr (assoc 'h host)))
                  (rects (herdr-layout-rects layout)))
              (let loop ((ts targets) (acc '()))
                (cond
                  ((null? ts) (reverse acc))
                  (else
                   (let* ((label (car (car ts)))
                          (pid   (cdr (car ts)))
                          (p     (assoc pid rects))
                          (r     (and p (cdr p))))
                     (if r
                         (let* ((rx (list-ref r 0)) (ry (list-ref r 1))
                                (rw (list-ref r 2)) (rh (list-ref r 3))
                                (x (+ hx (quotient (* (- rx ax) hw) aw)))
                                (y (+ hy (quotient (* (- ry ay) hh) ah)))
                                (w (quotient (* rw hw) aw))
                                (h (quotient (* rh hh) ah)))
                           (loop (cdr ts)
                                 (cons (cons label
                                             (list (cons 'handle #f)
                                                   (cons 'x x) (cons 'y y)
                                                   (cons 'w w) (cons 'h h)))
                                       acc)))
                         (loop (cdr ts) acc))))))))))

    ;; Focused iTerm AXScrollArea pixel frame — the tmux host-frame source.
    ;; Replace mode: herdr owns the sole scroll area, so the first match is
    ;; correct. Augment mode: the first may be the wrong split (documented
    ;; limitation). #f when iTerm isn't reachable.
    (define (herdr-host-frame)
      (let ((areas (ax-find-elements-named
                     "com.googlecode.iterm2" "AXScrollArea" "AXStaticText")))
        (and (pair? areas) (car areas))))

    ;; on-render side-effect for the chips path: read the current-tab layout
    ;; and host frame, synthesise chips for the just-snapshotted pane targets,
    ;; and surface them via hints-show. Skips hints-show when there is nothing
    ;; to paint (no host, no layout, no on-tab pane) so the overlay isn't shown
    ;; empty — digit dispatch still works off current-targets. Assumes
    ;; snapshot! has already run this render pass (so current-targets is set).
    (define (paint-pane-chips!)
      (let* ((layout  (herdr-list-json "pane layout"))
             (host    (herdr-host-frame))
             (entries (herdr-chip-entries current-targets layout host)))
        (when (pair? entries)
          (hints-show (ax-target-hints entries (current-chip-theme 'normal))))))

    ;; Constructor. on-render-fn snapshots the live list and merges the rows
    ;; into the block JSON so the rendered rows match the just-captured state.
    ;; With 'chips? #t on a panes block it also paints pane chips and installs
    ;; an on-leave-fn that hides them (mirrors iterm-panes). Chips are
    ;; panes-only — tabs/workspaces have no on-screen rects, so 'chips? is
    ;; ignored for those kinds.
    (define (make-herdr-list-block . opts)
      (let* ((alist  (apply props->alist opts))
             (kind   (alist-ref alist 'kind 'panes))
             (labels (alist-ref alist 'labels default-herdr-labels))
             (chips? (and (alist-ref alist 'chips? #f) (eq? kind 'panes))))
        (if chips?
            (list (cons 'type 'herdr-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (snapshot! kind labels)
                      (paint-pane-chips!)
                      (list (cons 'rows current-data))))
                  (cons 'on-leave-fn
                    (lambda () (hints-hide))))
            (list (cons 'type 'herdr-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (snapshot! kind labels)
                      (list (cons 'rows current-data))))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/herdr-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/herdr-list.js")))
