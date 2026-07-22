;; (modaliser blocks herdr-jump-legend) — block constructor for the herdr
;; jump space's Jump legend panel (jump-space-legend-overlay-k40,
;; docs/specs/herdr-jump-navigation.md "Legend"): one row per assigned jump
;; target — label, target name, kind — read from the Visit's snapshotted
;; assignment, names joined at render time. The sibling of (modaliser blocks
;; herdr-list), but display-only: no digit dispatch, no selection cursor,
;; no chips — the jump label is dispatched entirely through the FSM
;; provider edges (modaliser muxes herdr)'s herdr-jump-provider already
;; installs, so this block never mutates anything.
;;
;; (make-herdr-jump-legend-block . opts) → block-spec
;;
;; Opts:
;;   'assigned-fn  THUNK — zero-arg, returns the current Visit's assigned
;;                 jump-label list (jump-labels-assign's own ((label .
;;                 target) …) shape, target = ((kind . KIND) (id . ID))).
;;                 Threaded in rather than imported directly — this block
;;                 stays a generic UI component with no coupling to herdr's
;;                 jump-dispatch state; (modaliser muxes herdr) closes it
;;                 over *current-jump-assigned* when it builds the panel.
;;                 Default: a thunk returning '() (an empty legend).
;;
;; This block queries `workspace list` / `tab list` / `pane list` itself
;; (through current-herdr-list-runner, reused from (modaliser blocks
;; herdr-list) rather than a second shell-out seam) ONLY inside on-render-fn
;; — the overlay only calls a panel's on-render-fn once it actually renders
;; (show-delay elapsed), so a fast jump that never shows the overlay pays
;; nothing for these extra queries.

(define-library (modaliser blocks herdr-jump-legend)
  (export make-herdr-jump-legend-block
          ;; Pure ASSIGNED + three parsed `<x> list` envelopes → legend
          ;; rows, exported for unit tests (test seam 5, docs/specs/herdr-
          ;; jump-navigation.md "Test seams") — fed canned fixtures, no
          ;; live herdr needed.
          herdr-jump-legend-rows)
  (import (scheme base)
          (modaliser util)
          (modaliser json)
          (modaliser overlay-assets)
          ;; current-herdr-list-runner: the existing herdr-JSON test seam
          ;; (feedback_no_live_env_mutation_in_tests) — reused rather than a
          ;; second parallel one, since this block queries the exact same
          ;; `<x> list` commands the live-list blocks already do.
          (only (modaliser blocks herdr-list) current-herdr-list-runner))
  (begin

    ;; ((id . name) …) from a parsed `<x> list` envelope's result.ARRAY-KEY
    ;; array, keyed by ID-KEY, valued by NAME-KEY — falling back to the id
    ;; itself when NAME-KEY is absent/blank (docs/specs/herdr-jump-
    ;; navigation.md "Legend": "missing name → raw id" — a name gap never
    ;; drops the row). Mirrors herdr-list.sld's kind-spec array traversal,
    ;; but keyed BY id (not label-indexed) — the legend looks a name up by
    ;; id, it never assigns digit labels of its own.
    (define (herdr-jump-legend-name-map parsed array-key id-key name-key)
      (let ((arr (and parsed (json-ref (json-ref parsed "result") array-key))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let* ((item (vector-ref arr k))
                         (id   (json-ref item id-key))
                         (name (json-ref item name-key)))
                    (loop (+ k 1)
                          (if (string? id)
                              (cons (cons id (if (string? name) name id)) acc)
                              acc))))))))

    (define (herdr-jump-legend-name id names)
      (let ((hit (assoc id names)))
        (if hit (cdr hit) id)))

    ;; Kind → display noun for the legend's dimmed detail column. Mirrors
    ;; the Spaces rename (docs/specs/herdr-jump-navigation.md "Spaces
    ;; rename": labels only — code keeps the `workspace` stem).
    (define (herdr-jump-legend-kind-label kind)
      (case kind
        ((workspaces) "Space")
        ((agents)     "Agent")
        ((tabs)       "Tab")
        ((panes)      "Pane")
        (else "")))

    ;; ASSIGNED — jump-labels-assign's own ((label . target) …) shape,
    ;; already in gather order (spaces → agents → tabs → panes,
    ;; (modaliser muxes herdr)'s *current-jump-assigned* snapshot) — plus
    ;; the three parsed `<x> list` envelopes → legend rows ((label title
    ;; detail) …), same order. An unlabelled (#f) target is dropped, the
    ;; same tail convention jump-provider-result/jump-targets-of-kind use
    ;; in (modaliser muxes herdr): the legend can never show a row with no
    ;; live chip behind it. Agents and panes are both pane_id-keyed and
    ;; share the SAME pane-names map (row-title's "agent" field
    ;; convention, blocks/herdr-list.sld) — an agent's pane may be off the
    ;; current tab, so PANES-PARSED must be the UNSCOPED `pane list`.
    (define (herdr-jump-legend-rows assigned workspaces-parsed tabs-parsed panes-parsed)
      (let ((workspace-names (herdr-jump-legend-name-map
                                workspaces-parsed "workspaces" "workspace_id" "label"))
            (tab-names       (herdr-jump-legend-name-map
                                tabs-parsed "tabs" "tab_id" "label"))
            (pane-names      (herdr-jump-legend-name-map
                                panes-parsed "panes" "pane_id" "agent")))
        (let loop ((rest assigned) (acc '()))
          (if (null? rest)
              (reverse acc)
              (let* ((entry (car rest)) (label (car entry)) (target (cdr entry)))
                (loop (cdr rest)
                      (if label
                          (let* ((kind  (cdr (assoc 'kind target)))
                                 (id    (cdr (assoc 'id target)))
                                 (names (case kind
                                          ((workspaces) workspace-names)
                                          ((tabs)       tab-names)
                                          ((agents panes) pane-names)
                                          (else '()))))
                            (cons (list (cons 'label label)
                                        (cons 'title (herdr-jump-legend-name id names))
                                        (cons 'detail (herdr-jump-legend-kind-label kind)))
                                  acc))
                          acc)))))))

    (define (herdr-jump-legend-json subcmd) ((current-herdr-list-runner) subcmd))

    ;; Constructor. Non-interactive: no 'cursor-targets-fn, no
    ;; 'block-children digit range — dispatch already lives in the FSM
    ;; provider edges, the jump label here is display-only.
    (define (make-herdr-jump-legend-block . opts)
      (let* ((alist       (apply props->alist opts))
             (assigned-fn (alist-ref alist 'assigned-fn (lambda () '()))))
        (list (cons 'type 'herdr-jump-legend)
              (cons 'on-render-fn
                (lambda ()
                  (list (cons 'rows
                    (herdr-jump-legend-rows
                      (assigned-fn)
                      (herdr-jump-legend-json "workspace list")
                      (herdr-jump-legend-json "tab list")
                      (herdr-jump-legend-json "pane list")))))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/herdr-jump-legend.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/herdr-jump-legend.js")))
