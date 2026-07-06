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
;; No chips here — herdr-list renders a row list only. Pane chips (rects from
;; `herdr pane layout`, tmux-style) are the separate herdr-pane-chips leaf.

(define-library (modaliser blocks herdr-list)
  (export make-herdr-list-block
          herdr-list-current-targets
          herdr-list-current-labels
          herdr-list-focused-index
          herdr-list-refresh!
          ;; Pure JSON → (targets . rows) extractor, exported for unit tests
          ;; (fed a parsed `herdr <x> list` fixture, no live herdr needed).
          herdr-list-extract
          default-herdr-labels)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser json)
          (only (modaliser terminal) modaliser-tool-path)
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

    ;; Constructor. on-render-fn snapshots the live list and merges the rows
    ;; into the block JSON so the rendered rows match the just-captured
    ;; state. No on-leave-fn: with no chips there is nothing to tear down.
    (define (make-herdr-list-block . opts)
      (let* ((alist  (apply props->alist opts))
             (kind   (alist-ref alist 'kind 'panes))
             (labels (alist-ref alist 'labels default-herdr-labels)))
        (list (cons 'type 'herdr-list)
              (cons 'on-render-fn
                (lambda ()
                  (snapshot! kind labels)
                  (list (cons 'rows current-data)))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/herdr-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/herdr-list.js")))
