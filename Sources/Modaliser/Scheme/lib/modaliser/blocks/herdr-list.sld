;; (modaliser blocks herdr-list) — one block constructor for herdr's five
;; live lists (panes / tabs / workspaces / agents / worktrees). herdr's
;; socket-API CLI hands us the id, focused flag and label of every
;; pane/tab/workspace/agent directly as JSON, so — unlike the iTerm blocks —
;; there is NO AX walk, no UUID correlation and no empty-title fallback. The
;; lists differ mostly in which `herdr <x> list` to run and how to read each
;; row, so a single `kind`-parameterised block covers all five.
;;
;; The agents kind is the odd one out: its rows carry a `status` (from each
;; agent's `agent_status`) that the JS renders as a color-coded badge, and it
;; reorders status-priority (blocked → working → idle → unknown) BEFORE
;; assigning digit labels, so digit "1" always focuses the first blocked agent
;; (the differentiator). Panes / tabs / workspaces keep JSON order, no status.
;;
;; The worktrees kind is the other special case: its rows read NEITHER a plain
;; id field NOR a `focused` bool. The digit switch target is COMPUTED — a
;; tagged string ("ws:<open_workspace_id>" when the worktree is open, else
;; "br:<branch>" to open a dormant one) that (modaliser muxes herdr) parses at
;; key-press — and the CURRENT row is computed cross-field (a row is current
;; when its open_workspace_id equals result.source.source_workspace_id, both
;; riding in the same `worktree list` payload). Both are pure over the JSON, so
;; no re-query. No status badge; the open/dormant state is folded into the
;; dimmed detail text (● open / ○ dormant), reusing the renderer unchanged.
;;
;; Two kinds are SCOPED to a caller-supplied id, unlike workspaces/agents/
;; worktrees which stay global by design: panes to the displayed tab
;; (herdr-pane-group grove) and tabs to the focused workspace. Both funnel
;; through the same mechanism — a single `scope-id` parameter threaded via the
;; 'scope-id-fn block opt into snapshot! and herdr-list-extract, rather than
;; two parallel kind-specific parameters — because the shape is identical:
;; drop any row whose scope field doesn't match before labels are assigned, so
;; digits (and, for panes, chips) map to exactly the scoped subset. `scope-
;; field` below is the one place that says which JSON field each scoped kind
;; compares (panes → tab_id, tabs → workspace_id); #f degrades to unfiltered
;; — global — rather than an empty list, since #f means herdr was unreachable
;; or the caller has no scope to offer, not "nothing matches."
;;
;; (make-herdr-list-block 'kind 'panes|'tabs|'workspaces|'agents|'worktrees . opts)
;;   → block-spec
;;
;; The block exposes (herdr-list-current-targets) → ((label . id) …) — for the
;; worktrees kind the cdr is the computed tagged target, not a bare id — so the
;; parent group can build a hidden (key-range "1.." …) that dispatches each
;; digit to the matching target. The focus/switch ACTION lives in (modaliser
;; muxes herdr) — `agent focus <pane_id>` / `tab focus <id>` / `workspace focus
;; <id>` / the worktree smart-switch — not here, keeping this module UI-only
;; (it never shells a mutating op).
;;
;; ── Single-render invariant ──
;; State (current-targets / current-data / current-kind) is module-level, one
;; cell shared by all kinds. That is safe because the herdr variant tree
;; renders at most ONE herdr list per overlay frame: panes at the top level,
;; tabs under `open "t"`, workspaces under `open "w"`, agents under `open
;; "a"`, worktrees under `open "g"` — never two at once. Each render
;; overwrites the cell with the visible list. (The iTerm blocks use a
;; module-state cell per list; herdr collapses to one because these never
;; co-render.)
;;
;; A render is NOT guaranteed to have run by the time the digit key-range
;; reads the cell, though (herdr-fast-key-drops-k8): a group descent only
;; renders synchronously when the overlay is already visible
;; (modal-handle-key, state-machine.sld) — a fast leader→group→digit press
;; can reach the digit before that. current-kind exists so a reader can tell
;; a genuine snapshot of ITS kind apart from another kind's leftovers still
;; sitting in the shared cell, rather than trusting a bare (assoc label
;; current-targets) that could spuriously hit under the same digit label.
;;
;; ── Pane chips (panes kind, 'chips? #t) ──
;; With 'chips? #t the panes block also paints digit chips over the on-screen
;; herdr panes (mirroring iterm-panes' paint-and-snapshot! / hints-hide). Rects
;; come from `herdr pane layout` — per-pane cell rects scaled by the focused
;; iTerm AXScrollArea pixel frame, tmux-style. Two subtleties:
;;   • CANVAS-RELATIVE. herdr paints a left sidebar, so layout.area.x ≥ 26 —
;;     but that area is only the pane sub-region, NOT the full canvas the AX
;;     host frame maps to. Pane rects are already absolute cells within the
;;     full (sidebar-included) canvas, so no offset subtraction is applied;
;;     the per-cell pixel size instead divides by (area.x + area.width) ×
;;     (area.y + area.height) — the total canvas — not by area.width/height
;;     alone. See herdr-chip-entries below for the live verification.
;;   • SUBSET of rows, historically. `pane layout` covers only the CURRENT
;;     tab's splits; since pane-list-tab-local-k3, `pane list` (the row
;;     source) is scoped identically (dropped to the focused tab in the pure
;;     extractor, mirroring the tabs kind's workspace-scoping), so a listed
;;     pane always has a matching chip. The lookup-by-pane_id keying stays as
;;     the mechanism — it still matters for the degraded #f-scope-id case,
;;     where the row list reverts to global and an off-tab row again has no
;;     chip. Digit-jump still focuses such a row by id (via `agent focus`);
;;     only the visible chip is absent.
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
          ;; The kind that populated the current-targets/current-data cell
          ;; (herdr-fast-key-drops-k8) — the single shared cell (see the
          ;; single-render invariant above) means a caller checking targets
          ;; for its OWN kind must confirm the cell actually belongs to it;
          ;; digit dispatch below is the one caller that does.
          herdr-list-current-kind
          herdr-list-focused-index
          herdr-list-refresh!
          ;; Pure JSON → (targets . rows) extractor, exported for unit tests
          ;; (fed a parsed `herdr <x> list` fixture, no live herdr needed).
          herdr-list-extract
          ;; Pure chip-rect synthesis (targets + parsed `pane layout` + host
          ;; frame → labelled chip entries), exported for unit tests.
          herdr-chip-entries
          default-herdr-labels
          ;; Test seam (herdr-fast-key-drops-k8, mirrors current-herdr-query-
          ;; runner in (modaliser muxes herdr)): a test hands back canned
          ;; `herdr <x> list` JSON in place of a live query
          ;; (feedback_no_live_env_mutation_in_tests).
          current-herdr-list-runner)
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
    ;; rendered rows; current-kind names which kind last populated them, so
    ;; a caller can tell a genuine snapshot of ITS kind apart from another
    ;; kind's leftovers (herdr-fast-key-drops-k8 — see herdr-list-current-kind).
    (define current-targets '())   ;; ((label . id) …)
    (define current-data '())      ;; row alists: ((label title detail focused) …)
    (define current-kind #f)

    (define (herdr-list-current-targets) current-targets)
    (define (herdr-list-current-labels) (map car current-targets))
    (define (herdr-list-current-kind) current-kind)

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
    ;; errors, but a render must never break). Routed through
    ;; current-herdr-list-runner (mirrors current-herdr-query-runner in
    ;; (modaliser muxes herdr)) so a test can hand back canned JSON without a
    ;; live herdr session (feedback_no_live_env_mutation_in_tests).
    (define current-herdr-list-runner
      (make-parameter
        (lambda (subcmd)
          (let ((out (string-trim
                       (run-shell
                         (string-append path-prefix "herdr " subcmd " 2>/dev/null")))))
            (if (string=? out "")
                #f
                (guard (e (#t #f)) (json-parse out)))))))

    (define (herdr-list-json subcmd) ((current-herdr-list-runner) subcmd))

    ;; Per-kind spec: (cli-subcommand result-array-key id-key title-key).
    ;; The result envelope is {"result":{"<array-key>":[ … ]}} for every
    ;; list command; each element carries an id, a `focused` bool and a
    ;; human label. Panes and agents have no `label`, so their title falls
    ;; back to the agent name then the id. Agents key their digit target on
    ;; `pane_id` — `agent focus <pane_id>` is the universal cross-tab focus.
    ;; The worktrees kind leaves id-key / title-key #f: it computes both its
    ;; target and its title from several fields (see the worktree helpers), so
    ;; the extractor bypasses the plain-field path for it.
    (define (kind-spec kind)
      (cond
        ((eq? kind 'panes)
         (list "pane list" "panes" "pane_id" #f))
        ((eq? kind 'tabs)
         (list "tab list" "tabs" "tab_id" "label"))
        ((eq? kind 'workspaces)
         (list "workspace list" "workspaces" "workspace_id" "label"))
        ((eq? kind 'agents)
         (list "agent list" "agents" "pane_id" #f))
        ((eq? kind 'worktrees)
         (list "worktree list" "worktrees" #f #f))
        (else (error "herdr-list: unknown kind" kind))))

    ;; The JSON field a scoped kind's rows are filtered on, or #f for a kind
    ;; that stays global. panes → tab_id (scoped to the displayed tab,
    ;; pane-list-tab-local-k3); tabs → workspace_id (scoped to the focused
    ;; workspace, herdr-tabs-workspace-local-k3). One kind-keyed table rather
    ;; than two parallel scoping mechanisms — see the module header.
    (define (scope-field kind)
      (cond
        ((eq? kind 'panes) "tab_id")
        ((eq? kind 'tabs)  "workspace_id")
        (else #f)))

    ;; ─── Worktree computed fields ───────────────────────────────────
    ;; The worktrees kind reads no plain id / focused field: its digit target
    ;; and its current row are both computed over the parsed `worktree list`
    ;; payload. Kept pure (JSON → value) so the extractor tests feed fixtures.

    ;; Last non-empty "/"-separated segment of a path, e.g.
    ;; "/a/b/c" → "c", "/a/b/" → "b", "" → "". A worktree with no branch and
    ;; no label falls back to this so the row still shows something legible.
    (define (path-basename path)
      (let loop ((parts (string-split path "/")) (last ""))
        (cond
          ((null? parts) last)
          ((string=? (car parts) "") (loop (cdr parts) last))
          (else (loop (cdr parts) (car parts))))))

    ;; The digit switch target for one worktree row: the tagged string that
    ;; (modaliser muxes herdr)'s focus-fn parses at key-press, so no re-query.
    ;;   open   → "ws:<open_workspace_id>"  (jump to the live workspace)
    ;;   dormant→ "br:<branch>"             (open a fresh workspace on the branch)
    ;; A detached, dormant worktree has neither a live workspace nor a branch →
    ;; #f: it still renders as a row but carries no digit (nothing to switch to
    ;; through herdr's --workspace / --branch ops). Git branch names cannot
    ;; contain ':', so the "ws:" / "br:" prefix split is unambiguous.
    (define (worktree-target item)
      (let ((ws (json-ref item "open_workspace_id")))
        (if (string? ws)
            (string-append "ws:" ws)
            (let ((br (json-ref item "branch")))
              (and (string? br) (not (string=? br ""))
                   (string-append "br:" br))))))

    ;; #t when this worktree is the CURRENT one — the worktree open in the
    ;; source repo's focused workspace. Both values ride in the same payload
    ;; (the row's open_workspace_id vs result.source.source_workspace_id), so
    ;; the test is pure over the JSON. Guarded on BOTH being strings: json-ref
    ;; returns #f for a missing key, and a bare (equal? #f #f) would wrongly
    ;; mark every dormant worktree current when there is no source id.
    (define (worktree-current? item source-ws-id)
      (let ((ws (json-ref item "open_workspace_id")))
        (and (string? source-ws-id)
             (string? ws)
             (string=? ws source-ws-id))))

    ;; Worktree title: the branch, else — a detached worktree has none — the
    ;; herdr label, else the path's basename. A worktree always has a path, so
    ;; this yields "" only for a truly empty row.
    (define (worktree-title item)
      (let ((br (json-ref item "branch")))
        (if (and (string? br) (not (string=? br "")))
            br
            (let ((lab (json-ref item "label")))
              (if (and (string? lab) (not (string=? lab "")))
                  lab
                  (let ((path (json-ref item "path")))
                    (if (string? path) (path-basename path) "")))))))

    ;; Worktree detail: the path, with the open/dormant state folded in as a
    ;; leading marker (● open — has a live workspace; ○ dormant — on disk only)
    ;; so the state shows without a new badge or JS/CSS change. Leading (not
    ;; trailing) so it survives truncation of a long path.
    (define (worktree-detail item)
      (let ((path (json-ref item "path"))
            (open? (string? (json-ref item "open_workspace_id"))))
        (string-append (if open? "● " "○ ")
                       (if (string? path) path ""))))

    ;; Title for one row. Worktrees compute their own (branch → label → path
    ;; basename). Tabs/workspaces carry a `label`; panes don't, so a pane reads
    ;; its agent name (e.g. "claude"), falling back to the pane id.
    (define (row-title kind item id title-key)
      (cond
        ((eq? kind 'worktrees) (worktree-title item))
        (title-key
         (let ((v (json-ref item title-key)))
           (if (string? v) v id)))
        (else
         (let ((agent (json-ref item "agent")))
           (if (string? agent) agent id)))))

    ;; Secondary dimmed text. Panes show their cwd; agents show where they
    ;; live (D2 cross-scope annotation) — `tab_id` encodes both workspace and
    ;; tab (e.g. "w9:t1"), falling back to `workspace_id`; worktrees show their
    ;; path with a folded-in open/dormant marker; tabs/workspaces show nothing
    ;; (the label already identifies them).
    (define (row-detail kind item)
      (cond
        ((eq? kind 'panes)
         (let ((cwd (json-ref item "cwd"))) (if (string? cwd) cwd "")))
        ((eq? kind 'agents)
         (let ((tab (json-ref item "tab_id"))
               (ws  (json-ref item "workspace_id")))
           (cond ((string? tab) tab)
                 ((string? ws) ws)
                 (else ""))))
        ((eq? kind 'worktrees) (worktree-detail item))
        (else "")))

    ;; Status-priority rank for the agents list: blocked (most urgent) first,
    ;; then working, idle, and unknown / anything unrecognised last (D7). Drives
    ;; the pre-label reorder so digit "1" always hits the first blocked agent.
    (define (agent-status-rank status)
      (cond ((equal? status "blocked") 0)
            ((equal? status "working") 1)
            ((equal? status "idle")    2)
            (else                      3)))

    ;; Reorder raw agent entries status-priority, STABLE within each band (so a
    ;; band keeps its input pane_id order). Appending four filtered bands is
    ;; inherently stable and needs no sort primitive or mutable pairs — LispKit
    ;; ships neither a stable list-sort nor set-cdr!. `raw` entries carry their
    ;; status at the 'status key.
    (define (order-agents-by-status raw)
      (let ((band (lambda (rank)
                    (filter (lambda (e)
                              (= rank (agent-status-rank (cdr (assoc 'status e)))))
                            raw))))
        (append (band 0) (band 1) (band 2) (band 3))))

    ;; Pure extractor: parsed `herdr <x> list` JSON + kind + labels +
    ;; scope-id → (targets . rows). targets = ((label . id) …) for the
    ;; first (length labels) entries; rows = every entry as an alist ((label
    ;; title detail focused) plus, for the agents kind only, status). An
    ;; entry past the label supply still renders (blank key, no dispatch).
    ;; Exported so a fixture-fed test needs no live herdr.
    ;;
    ;; scope-id scopes whichever kind's scope-field is non-#f (panes → tab_id,
    ;; tabs → workspace_id; workspaces/agents/worktrees ignore it — global by
    ;; design): a row whose scope field doesn't match scope-id is dropped in
    ;; phase 1, before labels are assigned, so digits map to exactly the
    ;; scoped subset. #f (herdr unreachable, or the kind isn't scoped) degrades
    ;; to unfiltered.
    ;;
    ;; The worktrees kind computes its digit target (a tagged
    ;; open-workspace-id-or-branch) and its current row (open_workspace_id ==
    ;; result.source.source_workspace_id) in phase 1 rather than reading a plain
    ;; id / `focused` field; it too carries no status and skips the reorder.
    ;;
    ;; Three phases, so the agents kind can reorder BEFORE labels are assigned:
    ;;  1. gather   — one raw entry per item, in JSON order; a scoped kind also
    ;;                filters by scope-id here.
    ;;  2. reorder  — agents only: status-priority (blocked-first), stable band.
    ;;  3. label    — walk the (possibly reordered) entries, assigning digit
    ;;                labels and building targets so digit "1" = first row.
    ;; The non-agents kinds skip phase 2 and carry no status.
    (define (herdr-list-extract kind labels parsed scope-id)
      (let* ((spec       (kind-spec kind))
             (array-key  (list-ref spec 1))
             (id-key     (list-ref spec 2))
             (title-key  (list-ref spec 3))
             (agents?    (eq? kind 'agents))
             (worktrees? (eq? kind 'worktrees))
             ;; The scope field for this kind, or #f when it stays global.
             ;; #f scope-id (no scope known — herdr unreachable) degrades to
             ;; unfiltered rather than an empty list.
             (scope-key  (scope-field kind))
             (scoped?    (and scope-key (string? scope-id)))
             (arr (and parsed
                       (json-ref (json-ref parsed "result") array-key)))
             (items (if (vector? arr) arr #()))
             ;; The current-worktree datum rides ONCE in the payload
             ;; (result.source.source_workspace_id); every worktree row compares
             ;; its open_workspace_id against it, so compute it once here and
             ;; thread it in. json-ref is #f-safe, so a #f parse degrades to #f.
             (source-ws-id (and worktrees?
                                (json-ref (json-ref (json-ref parsed "result")
                                                    "source")
                                          "source_workspace_id")))
             ;; Phase 1 — raw entries in JSON order. `has-id` records whether a
             ;; real target was built (only those become digit targets); for
             ;; worktrees the target is the computed tagged string; `status` is
             ;; the agent_status string for agents, else #f. A row outside the
             ;; scope (scoped?) is skipped entirely, so it never reaches
             ;; phase 3's label assignment.
             (raw
              (let loop ((k 0) (acc '()))
                (if (>= k (vector-length items))
                    (reverse acc)
                    (let ((item (vector-ref items k)))
                      (if (and scoped?
                               (not (equal? (json-ref item scope-key) scope-id)))
                          (loop (+ k 1) acc)
                          (let* (;; Digit target: worktrees compute a tagged
                                 ;; string (or #f when unswitchable); other
                                 ;; kinds read the plain id field.
                                 (target  (if worktrees?
                                              (worktree-target item)
                                              (json-ref item id-key)))
                                 (idstr   (if (string? target) target ""))
                                 ;; `focused`: worktrees compute the current row
                                 ;; cross-field; other kinds read herdr's
                                 ;; `focused`.
                                 (focused (if worktrees?
                                              (worktree-current? item source-ws-id)
                                              (eq? (json-ref item "focused") #t)))
                                 (status  (and agents?
                                               (let ((s (json-ref item "agent_status")))
                                                 (if (string? s) s "unknown")))))
                            (loop (+ k 1)
                                  (cons (list (cons 'id idstr)
                                              (cons 'has-id (string? target))
                                              (cons 'focused focused)
                                              (cons 'title (row-title kind item idstr title-key))
                                              (cons 'detail (row-detail kind item))
                                              (cons 'status status))
                                        acc))))))))
             ;; Phase 2 — agents reorder status-priority; other kinds untouched.
             (entries (if agents? (order-agents-by-status raw) raw)))
        ;; Phase 3 — assign labels over the final sequence.
        (let loop ((es entries) (labs labels) (targets '()) (rows '()))
          (cond
            ((null? es)
             (cons (reverse targets) (reverse rows)))
            (else
             (let* ((e       (car es))
                    (idstr   (cdr (assoc 'id e)))
                    (has-id  (cdr (assoc 'has-id e)))
                    (status  (cdr (assoc 'status e)))
                    (has-lab (pair? labs))
                    (label   (if has-lab (car labs) "")))
               (loop (cdr es)
                     (if has-lab (cdr labs) labs)
                     (if (and has-lab has-id)
                         (cons (cons label idstr) targets)
                         targets)
                     ;; status rides on the row ONLY for agents — the JS badge
                     ;; renderer keys on its presence, so panes/tabs/workspaces
                     ;; rows stay visually unchanged.
                     (cons (let ((base (list (cons 'label label)
                                             (cons 'title (cdr (assoc 'title e)))
                                             (cons 'detail (cdr (assoc 'detail e)))
                                             (cons 'focused (cdr (assoc 'focused e))))))
                             (if status
                                 (append base (list (cons 'status status)))
                                 base))
                           rows))))))))

    ;; Query herdr, extract, store into the shared cell. Returns targets.
    ;; scope-id is threaded straight into herdr-list-extract — see its
    ;; docstring; only a scoped kind (panes, tabs) uses it.
    (define (snapshot! kind labels scope-id)
      (let* ((spec   (kind-spec kind))
             (parsed (herdr-list-json (list-ref spec 0)))
             (pair   (herdr-list-extract kind labels parsed scope-id)))
        (set! current-targets (car pair))
        (set! current-data    (cdr pair))
        (set! current-kind    kind)
        current-targets))

    ;; On-demand refresh for the digit key-range: a leader-then-digit press
    ;; faster than the overlay delay can fire before the on-render snapshot
    ;; ran, so the dispatcher re-snapshots the right kind and looks again.
    ;; Takes the same scope-id as the on-render path so a refresh mid-digit-
    ;; press stays scoped identically.
    (define (herdr-list-refresh! kind scope-id)
      (snapshot! kind default-herdr-labels scope-id)
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
    ;;
    ;; Cell→pixel scale is CANVAS-relative, not area-relative. Verified live
    ;; (2026-07-14, herdr 0.7.3): `layout.area` is only the pane sub-region —
    ;; it excludes herdr's left sidebar — while pane `rect`s are already
    ;; absolute cells within the FULL canvas (sidebar included), and so is the
    ;; iTerm AXScrollArea host frame (confirmed against the live session's
    ;; own column/row count via iTerm's scripting bridge: area.x + area.width
    ;; == the session's total columns). So the total canvas size is
    ;; (area.x + area.width) × (area.y + area.height), pane rects need no
    ;; offset subtraction, and the per-cell pixel size divides by the TOTAL,
    ;; not by area.width/area.height alone — dividing by area.width alone
    ;; over-widens each cell (it pretends the sidebar's columns don't exist),
    ;; which combined with the offset subtraction shifted every chip left of
    ;; its pane. quotient (multiply-then-divide) keeps integer precision,
    ;; exactly as tmux's chip-entries does. A target whose pane is absent from
    ;; this (current-tab) layout is skipped.
    (define (herdr-chip-entries targets layout host)
      (let ((area (and layout (herdr-layout-area layout))))
        (if (not (and area host))
            '()
            (let* ((ax (list-ref area 0)) (ay (list-ref area 1))
                   (aw (list-ref area 2)) (ah (list-ref area 3))
                   (total-w (+ ax aw)) (total-h (+ ay ah))
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
                                (x (+ hx (quotient (* rx hw) total-w)))
                                (y (+ hy (quotient (* ry hh) total-h)))
                                (w (quotient (* rw hw) total-w))
                                (h (quotient (* rh hh) total-h)))
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
    ;; ignored for those kinds. 'scope-id-fn is an optional zero-arg thunk,
    ;; called fresh on every render/refresh (see the module header) — only a
    ;; scoped kind's caller (panes, tabs) passes one.
    (define (make-herdr-list-block . opts)
      (let* ((alist    (apply props->alist opts))
             (kind     (alist-ref alist 'kind 'panes))
             (labels   (alist-ref alist 'labels default-herdr-labels))
             (scope-fn (alist-ref alist 'scope-id-fn #f))
             (chips?   (and (alist-ref alist 'chips? #f) (eq? kind 'panes))))
        (if chips?
            (list (cons 'type 'herdr-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (snapshot! kind labels (and scope-fn (scope-fn)))
                      (paint-pane-chips!)
                      (list (cons 'rows current-data))))
                  (cons 'on-leave-fn
                    (lambda () (hints-hide))))
            (list (cons 'type 'herdr-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (snapshot! kind labels (and scope-fn (scope-fn)))
                      (list (cons 'rows current-data))))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/herdr-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/herdr-list.js")))
