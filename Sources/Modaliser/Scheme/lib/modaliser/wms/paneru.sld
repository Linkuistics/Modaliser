;; (modaliser wms paneru) — paneru window-manager ops and the
;; installation predicate.
;;
;; paneru (karinushka/paneru) is an external sliding window manager: windows
;; live on an infinite horizontal strip and opening one never resizes its
;; neighbours. A daemon owns the strip; the `paneru` binary talks to it over a
;; Unix socket. Modaliser is a *client* of it, never a reimplementation.
;;
;; Quick start (prefix-style import, so the bare op names don't collide with
;; (modaliser window-actions)'s layout ops):
;;
;;   (import (prefix (modaliser wms paneru) paneru:))
;;
;;   (define windows-screen
;;     (if (paneru:installed?)
;;         (open …)          ; a screen built from the ops below
;;         (open …)))        ; the Window-layout-op screen
;;
;; That `if` is the **Paneru-installed composition**: one branch, taken once at
;; config load (ADR-0018). It tests *installation*, never daemon liveness — a
;; liveness test would make the meaning of a key depend on whether Modaliser or
;; the paneru daemon won the startup race, whereas installation cannot race. A
;; daemon that is down degrades to the established empty-output path.
;;
;; NO SCREEN, and no keys. Which op reaches which key under which label is the
;; user's (ADR-0021); every op below is a **facility**, its correctness fixed by
;; paneru's own CLI rather than by anybody's preference.
;;
;; `wms/` is a new category, peer to `muxes/`, `apps/` and `tools/`. This file
;; is shaped like `muxes/zellij.sld` and is deliberately missing that file's two
;; structural pieces: there is **no backend record** and **no `wiring`
;; fragment**, because paneru sits behind no façade. It is not a
;; (modaliser terminal) backend, it contributes no Terminal-context-map entry,
;; and it has nothing for the façade to dispatch to. Nothing replaces them — a
;; reader coming from `zellij.sld` should read that absence as the point.
;;
;; Seven ops, not twenty. The rest of paneru's surface — `resize`, `fullwidth`,
;; `stack`/`unstack`, `equalize`, `balance`, `manage`, the workspace verbs, the
;; display verbs, `focus first`/`last`/`<n>` — is deliberately absent. Each
;; further op is a config-visible follow-up costing one line here, not
;; speculative library surface.
;;
;; Fire-and-forget, with no error channel. Probed against the live daemon
;; (2026-08-04): an unrecognised command exits 0 and prints nothing — the daemon
;; silently discards it. A wrong wire form therefore fails *invisibly*, which is
;; why each op's exact command string is pinned by a test rather than trusted.
;; Note in particular that the wire form is space-separated
;; (`window focus east`); the underscored spelling (`window_focus_east`) is the
;; TOML *binding name* in the user's paneru.toml, not something send-cmd accepts.
;;
;; Every outward call goes through the (modaliser shell) seam (ADR-0023), which
;; ships with no runner installed — so under `swift test` this library reaches
;; no live daemon however many ops fire. See docs/specs/paneru-window-management.md.
;;
;; ── The Strip listing ──────────────────────────────────────────────
;;
;; Beside the ops, this library owns the **Strip listing**: the active virtual
;; workspace's windows as overlay rows, each reachable by a **jump label**. Its
;; rows come from paneru and its focusing comes from Modaliser, joined on
;; window id (ADR-0024) — paneru knows the strip's membership and order,
;; Modaliser holds the `ownerPid` that `focus-window` needs, and neither knows
;; the other's half.
;;
;;   query → parse → join → assign labels → provided edges + the block's rows
;;
;; The first stage is the only outward shell call; the middle two are pure
;; functions tested by direct call; the last two run inside an **Edge
;; provider** at come-to-rest, so the rendered rows and the live jump labels
;; are one snapshot and cannot disagree. `window focus <n>` is deliberately NOT
;; how a listed row is targeted — a column number is not derivable from a
;; listed window, and stacked columns make position arithmetic silently wrong
;; (ADR-0024).
;;
;; Two seams, both here: `current-shell-runner` for everything paneru-side, and
;; `strip-provider`'s 'enumerate for Modaliser's own window enumeration. The
;; second is a DETERMINISM seam, not an isolation one — the enumeration is an
;; uncached accessibility sweep of every running app, so a provider test that
;; let it run would assert against whatever happened to be open on the
;; developer's desktop.

(define-library (modaliser wms paneru)
  (export
          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;;
          ;; All 0-arg thunks that land straight in a `(key K L op)` slot,
          ;; each one `paneru send-cmd …` and nothing else.
          ;;
          ;;   focus-west / focus-east  move focus one column along the strip
          ;;   swap-west  / swap-east   move the focused window one column
          ;;   grow / shrink            next / previous preset_column_widths entry
          ;;   center                   scroll the strip to centre the focused window
          focus-west  focus-east
          swap-west   swap-east
          grow        shrink
          center
          ;; ── The composition predicate ──────────────────────────────
          ;;
          ;; #t when the `paneru` binary resolves on the derived tool path
          ;; (ADR-0017). The **Paneru-installed composition** test — see the
          ;; header on why this is installation and not liveness.
          installed?
          ;; ── The Strip listing ─────────────────────────────────────
          ;;
          ;; strip-provider  — keyword opts (three alphabets, 'panel-label,
          ;;                   'enumerate) → the **Edge provider** a screen
          ;;                   binds on its 'provider slot. The engine
          ;;                   invokes it with the id of the state it was
          ;;                   lowered onto (provider-state-id-k9), which is
          ;;                   the parent of every narrowing prefix state it
          ;;                   mints and those states' up-edge target.
          ;; strip-listing   — → the Strip-listing block spec, reading the
          ;;                   SAME **Strip snapshot** the provider took, so
          ;;                   the rows can never disagree with the labels.
          strip-provider
          strip-listing
          ;; Pure, exported for unit tests (docs/specs/paneru-window-
          ;; management.md "Test seams" 4/5/6) — each is fed canned data by
          ;; direct call, with no seam under it:
          ;;   parse-strip-windows    payload text → strip rows
          ;;   join-strip-targets     rows × enumeration → **Strip targets**
          ;;   strip-focus-choice     one target → focus-window's choice alist
          ;;   strip-provider-result  assigned labels → edges + provided states
          parse-strip-windows
          join-strip-targets
          strip-focus-choice
          strip-provider-result)
  (import (scheme base)
          (modaliser shell)
          (modaliser util)
          ;; The payload reader. Portable — (modaliser json) depends only on
          ;; (scheme base) and (scheme char).
          (modaliser json)
          ;; jump-labels-assign: the parameterised prefix-free label
          ;; assignment utility, escalating one-key labels into two-key ones
          ;; exactly as far as this Visit's strip length demands. It knows
          ;; nothing of paneru — the alphabets arrive from the user (ADR-0021).
          (modaliser jump-labels)
          ;; edge / provided-state: the FSM primitives the provider lowers a
          ;; label assignment onto. Both portable — (modaliser fsm) imports
          ;; only (scheme base) (scheme write) (modaliser util).
          (only (modaliser fsm) edge provided-state)
          ;; The Strip-listing renderer. The dependency runs THIS way only:
          ;; the block is a generic labelled-row component that knows nothing
          ;; of paneru, and this library composes it.
          (only (modaliser blocks paneru-strip) make-paneru-strip-block)
          ;; focus-window is ADR-0024's whole mechanism — Modaliser's own
          ;; by-id focus, the half paneru cannot do. list-current-space-windows
          ;; is the default 'enumerate: the current-space AX sweep, whose
          ;; entries carry the windowId the join keys on and the ownerPid it
          ;; recovers. Never reached from a test — 'enumerate is injected and
          ;; a Terminal state's entry is asserted structurally, never fired.
          (only (modaliser window) focus-window list-current-space-windows)
          ;; Narrowly, for the PATH preamble below. Every CLI-native backend
          ;; in the tree reaches into the terminal façade for this one string;
          ;; relocating it to a neutral home is a separate concern.
          (only (modaliser terminal) modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that does
    ;; not include the prefixes `paneru` is installed under, so every
    ;; shell-out is prefixed with the derived tool path (ADR-0017 Layer 1).
    ;; Baked once at library load, exactly as tmux, zellij and the app
    ;; backends bake theirs.
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Ops ────────────────────────────────────────────────────────
    ;;
    ;; One helper, seven one-line ops. ARGS is the space-separated command
    ;; tail exactly as the daemon expects it; stderr is discarded on the
    ;; same terms as every other backend — a missing binary must degrade to
    ;; the empty string, never raise, because a leader press must never
    ;; raise (ADR-0017).
    (define (send-cmd args)
      (run-shell
        (string-append path-prefix "paneru send-cmd " args " 2>/dev/null")))

    (define (focus-west) (send-cmd "window focus west"))
    (define (focus-east) (send-cmd "window focus east"))

    (define (swap-west)  (send-cmd "window swap west"))
    (define (swap-east)  (send-cmd "window swap east"))

    (define (grow)       (send-cmd "window grow"))
    (define (shrink)     (send-cmd "window shrink"))

    (define (center)     (send-cmd "window center"))

    ;; ─── Installation ───────────────────────────────────────────────
    ;;
    ;; `command -v paneru` through the derived tool path, the same probe
    ;; ADR-0017 Layer 2 runs for a backend's CLI tool. Empty output — a
    ;; missing binary, or a bare engine with no shell runner installed —
    ;; reads as absent, so an unbootstrapped engine composes the non-paneru
    ;; screen and nothing else in this library ever runs.
    (define (installed?)
      (not (string=? ""
             (string-trim
               (run-shell
                 (string-append path-prefix
                                "command -v paneru 2>/dev/null"))))))

    ;; ─── The query ──────────────────────────────────────────────────
    ;;
    ;; The one read-only outward call, through the same seam every op uses.
    ;; A down daemon, a missing binary, or a bare engine with no runner all
    ;; answer "" here, and the parse below turns "" into no rows — the
    ;; established empty-output degradation (ADR-0017, ADR-0023), never an
    ;; error reaching a leader press.
    (define (query-strip-state)
      (run-shell
        (string-append path-prefix "paneru query state --json 2>/dev/null")))

    ;; ─── The parse (pure) ───────────────────────────────────────────
    ;;
    ;; Payload text → the ACTIVE virtual workspace's windows in strip order,
    ;; each row an alist ('window-id 'bundle-id 'app 'title 'focused
    ;; 'floating).
    ;;
    ;; The active workspace is the `virtual_workspaces` entry whose `active`
    ;; is true — NOT the one matching `active.virtual_workspace_number`. The
    ;; live daemon reports two workspaces both numbered 1 (on different
    ;; native workspaces), so the number is not a key. Getting this wrong
    ;; lists the wrong desktop's windows, or none.
    ;;
    ;; Malformed, empty or unexpectedly-shaped input yields '() rather than
    ;; raising, at every level: json-parse raises on bad text (caught here),
    ;; json-ref answers #f for a missing key or a non-object, and each array
    ;; walk checks `vector?` before indexing.
    (define (parse-strip-windows text)
      (let* ((parsed    (guard (e (#t #f)) (json-parse text)))
             (workspaces (json-ref parsed "virtual_workspaces")))
        (if (not (vector? workspaces))
            '()
            (let loop ((k 0))
              (cond
                ((>= k (vector-length workspaces)) '())
                ;; json-ref answers #f for both "absent" and "false", which
                ;; is exactly the test wanted here: only a literal true
                ;; selects a workspace.
                ((json-ref (vector-ref workspaces k) "active")
                 (strip-rows-of (vector-ref workspaces k)))
                (else (loop (+ k 1))))))))

    ;; One parsed virtual-workspace object → its `windows` array as rows, in
    ;; array order (which IS strip order, left to right). A row whose
    ;; `window_id` is not a number is dropped: the id is the join key and the
    ;; state id, so a row without one can be neither listed usefully nor
    ;; focused.
    (define (strip-rows-of workspace)
      (let ((windows (json-ref workspace "windows")))
        (if (not (vector? windows))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length windows))
                  (reverse acc)
                  (let* ((w  (vector-ref windows k))
                         (id (json-ref w "window_id")))
                    (loop (+ k 1)
                          (if (number? id)
                              (cons (list (cons 'window-id id)
                                          (cons 'bundle-id (or (json-ref w "bundle_id") ""))
                                          (cons 'app       (or (json-ref w "app_name") ""))
                                          (cons 'title     (or (json-ref w "title") ""))
                                          (cons 'focused   (if (json-ref w "focused") #t #f))
                                          (cons 'floating  (if (json-ref w "floating") #t #f)))
                                    acc)
                              acc))))))))

    ;; ─── The join (pure) ────────────────────────────────────────────
    ;;
    ;; ROWS × ENUMERATION → one **Strip target** per row, in strip order:
    ;; the row's own fields plus the 'owner-pid recovered by matching
    ;; 'window-id against the enumeration's 'windowId. A row that finds no
    ;; match keeps its place with 'owner-pid #f — listed and labelled, but
    ;; not focusable (ADR-0024 Consequences).
    ;;
    ;; ENUMERATION is an ARGUMENT rather than a call, and that is the whole
    ;; reason this is a pure function: the live sweep happens one level up,
    ;; in strip-provider, behind an injectable option.
    (define (join-strip-targets rows enumeration)
      (map (lambda (row)
             (cons (cons 'owner-pid
                         (enumeration-pid-for (cdr (assoc 'window-id row)) enumeration))
                   row))
           rows))

    ;; ENUMERATION entry whose 'windowId is ID → its 'ownerPid, else #f.
    ;; Linear per row: a strip holds tens of windows, not thousands, and a
    ;; hashtable here would buy nothing measurable against the subprocess
    ;; spawn and the AX sweep this join sits between.
    (define (enumeration-pid-for id enumeration)
      (let loop ((rest enumeration))
        (cond
          ((null? rest) #f)
          ((equal? id (alist-ref (car rest) 'windowId))
           (alist-ref (car rest) 'ownerPid))
          (else (loop (cdr rest))))))

    ;; #t when a **Strip target** has the pid focus-window needs. An
    ;; unmatched target still renders and still consumes its label; it just
    ;; gets no edge.
    (define (strip-target-focusable? target)
      (number? (alist-ref target 'owner-pid)))

    ;; ─── Focusing (pure) ────────────────────────────────────────────
    ;;
    ;; One **Strip target** → the choice alist focus-window reads: 'ownerPid
    ;; (without which it no-ops), 'windowId, and 'text as a title hint. Split
    ;; out as a pure function precisely so the key spelling is pinned by a
    ;; direct-call test — the alternative was a third seam over focus-window
    ;; itself, and the spec's seam count is two.
    (define (strip-focus-choice target)
      (list (cons 'ownerPid (alist-ref target 'owner-pid))
            (cons 'windowId (alist-ref target 'window-id))
            (cons 'text     (or (alist-ref target 'title) ""))))

    ;; ─── The Strip snapshot ─────────────────────────────────────────
    ;;
    ;; The provider's per-Visit gather → join → assign result, read by the
    ;; block at render. One cell, written at come-to-rest and read once the
    ;; overlay's show delay elapses — so the rows the user sees are the exact
    ;; assignment their keypress dispatches through, and a label pressed
    ;; faster than the overlay appears still works.
    (define *current-strip-assigned* '())

    (define (set-current-strip-assigned! assigned)
      (set! *current-strip-assigned* assigned))

    ;; ─── Lowering an assignment onto the FSM ────────────────────────
    ;;
    ;; A **Strip target**'s Terminal dispatch state id. Free-form: a Terminal
    ;; state deactivates before any presentation code consults a state id's
    ;; shape, so this needs collision-freedom across live targets and nothing
    ;; else. The window id supplies exactly that.
    (define (strip-target-state-id target)
      (string-append "paneru-strip-target/"
                     (number->string (alist-ref target 'window-id))))

    ;; A narrowing prefix state's id — OWNER-ID + "/" + leader, the
    ;; convention permanent child states use (fsm-child-id). This shape is
    ;; NOT free: a resting provided state survives as a Visit owner across
    ;; keystrokes, so the presentation façade reads it the way it reads a
    ;; permanent state, and modal-current-path's strip-id-prefix `substring`s
    ;; the parent's id off the child's to derive a breadcrumb segment. Any
    ;; other shape yields a garbled segment or raises outright.
    (define (strip-prefix-state-id owner-id leader)
      (string-append owner-id "/" leader))

    ;; One provided Terminal state per focusable labelled target: entry
    ;; focuses the window by id, no edges — Terminal, so firing it halts the
    ;; engine and the modal exits, which is what a jump means. 'payload '()
    ;; (an empty alist, not the default #f) is never read here — a Terminal
    ;; state deactivates first — but it keeps the shape uniform with the
    ;; prefix state below, where the payload very much does matter.
    (define (strip-terminal-state target)
      (provided-state (strip-target-state-id target)
        'payload '()
        'entry (lambda () (focus-window (strip-focus-choice target)))))

    ;; Merge (LEADER SECOND . TARGET) into BY-LEADER — an alist of
    ;; leader → ((second . target) …), preserving first-seen leader order and
    ;; each leader's own second-key order. Strip lengths are small, so the
    ;; append buys ordering simplicity over a smarter accumulator.
    (define (strip-merge-leader-group by-leader leader second target)
      (if (assoc leader by-leader)
          (map (lambda (kv)
                 (if (string=? (car kv) leader)
                     (cons leader (append (cdr kv) (list (cons second target))))
                     kv))
               by-leader)
          (append by-leader (list (cons leader (list (cons second target)))))))

    ;; One leader's provided PREFIX (resting) state. Four things about it are
    ;; load-bearing, and every one of them fails silently if guessed at:
    ;;
    ;;  - its id is OWNER-ID + "/" + leader (see strip-prefix-state-id);
    ;;  - its 'up edge targets OWNER-ID, or backspace does not un-narrow and
    ;;    ancestors-within-tree stops the climb early;
    ;;  - its 'payload carries the two-layer node shape `screen` lowers a
    ;;    registered root's payload into — a 'children list holding the block,
    ;;    plus a 'display clause with one panel referencing it by type.
    ;;    fsm-resolved-payload hands this alist to the façade as
    ;;    modal-current-node, and the panel-grid renderer resolves 'children +
    ;;    'display off whatever that is (ADR-0011), so the UNCHANGED renderer
    ;;    draws the narrowed listing. A payload-less prefix state narrows into
    ;;    a blank screen with no indication of which second keys are live;
    ;;  - it carries its OWN 'provider, re-minting exactly the Terminal states
    ;;    its own second-key edges target. Not an optimisation: provided
    ;;    states are Visit-scoped, and stepping into this state BEGINS a new
    ;;    Visit whose provided table holds only what this state's provider
    ;;    returns. Without it the second key resolves to a state nobody minted.
    ;;
    ;; PAIRS is the ((second . target) …) survivor list the owner's provider
    ;; already computed, so the re-mint and the narrowed block are both closed
    ;; over it — no second paneru query, no re-narrowing, and the narrowed
    ;; rows are provably the same targets the second-key edges dispatch to.
    ;;
    ;; PANEL-LABEL rides in from the user (ADR-0021): a label authored in a
    ;; library file sits inside the decision-free contract's spirit even where
    ;; check-decision-free.sh's grep cannot see it.
    (define (strip-prefix-state owner-id panel-label leader pairs)
      (let ((second-edges
              (map (lambda (p) (edge (car p) (strip-target-state-id (cdr p)))) pairs)))
        (apply provided-state (strip-prefix-state-id owner-id leader)
          'payload (list (cons 'children
                               (list (make-paneru-strip-block
                                       'assigned-fn (lambda () pairs))))
                         (cons 'display
                               (list (cons 'panels
                                           (list (list (cons 'label panel-label)
                                                       (cons 'span 'wide)
                                                       (cons 'rows (list (cons 'block 'paneru-strip)))))))))
          ;; This state's OWN id is handed in as the provider argument and
          ;; ignored: every state re-minted here is Terminal, so none of them
          ;; needs a parent id.
          'provider (lambda (own-id)
                      (list (cons 'states
                                  (map (lambda (p) (strip-terminal-state (cdr p))) pairs))))
          (edge 'up owner-id)
          second-edges)))

    ;; ASSIGNED ((label . target) …) → this Visit's provider result: 'edges
    ;; (one direct edge per single-key label, one per USED leader) and
    ;; 'states (one Terminal state per single-key target, one prefix state
    ;; per leader — a leader's own targets' Terminal states live in the
    ;; PREFIX state's provider, not here; see strip-prefix-state).
    ;;
    ;; Two kinds of target are dropped from the edge set and from nothing
    ;; else — both still render as rows:
    ;;   - UNLABELLED (#f): past both pools' exhaustion.
    ;;   - UNMATCHED (no 'owner-pid): the join found nothing to focus.
    ;; Dropping an unmatched target here rather than during ASSIGNMENT is the
    ;; deliberate choice: skipping it earlier would renumber every label below
    ;; it on a single transient join miss. A miss costs one dead key.
    ;;
    ;; A leader whose every second key is dropped therefore contributes no
    ;; group at all, so the leader key itself stays dead rather than narrowing
    ;; into an empty listing.
    (define (strip-provider-result assigned owner-id panel-label)
      (let loop ((rest assigned) (edges '()) (states '()) (by-leader '()))
        (if (null? rest)
            (let ((leader-edges
                    (map (lambda (kv) (edge (car kv) (strip-prefix-state-id owner-id (car kv))))
                         by-leader))
                  (prefix-states
                    (map (lambda (kv) (strip-prefix-state owner-id panel-label (car kv) (cdr kv)))
                         by-leader)))
              (list (cons 'edges (append (reverse edges) leader-edges))
                    (cons 'states (append (reverse states) prefix-states))))
            (let* ((entry  (car rest))
                   (label  (car entry))
                   (target (cdr entry)))
              (cond
                ((or (not label) (not (strip-target-focusable? target)))
                 (loop (cdr rest) edges states by-leader))
                ((= (string-length label) 1)
                 (loop (cdr rest)
                       (cons (edge label (strip-target-state-id target)) edges)
                       (cons (strip-terminal-state target) states)
                       by-leader))
                (else
                  (loop (cdr rest) edges states
                        (strip-merge-leader-group
                          by-leader
                          (substring label 0 1)
                          (substring label 1 (string-length label))
                          target))))))))

    ;; ─── The Edge provider ──────────────────────────────────────────
    ;;
    ;; (strip-provider 'single-alphabet … 'leader-alphabet … 'second-alphabet …
    ;;                 ['panel-label STRING] ['enumerate THUNK])
    ;;   → a 1-arg procedure for a state's 'provider slot.
    ;;
    ;; All three alphabets come from the USER: jump labels are keys, and no
    ;; library file may author a key (ADR-0021). None is defaulted — an
    ;; omitted alphabet yields no labels rather than a library-chosen one.
    ;;
    ;; 'enumerate is the second test seam (see the header): a 0-arg thunk
    ;; returning Modaliser's window enumeration, defaulting to the
    ;; current-space AX sweep. It is NOT a cost lever, though it was once
    ;; offered as one: the wider, cached, staler `list-windows` measured 13ms
    ;; against this one's 14, inside the noise and with the same tail. What a
    ;; swap would buy is a different HIT RATE for the join, nothing else.
    ;;
    ;; OWNER-ID is the id of the state this provider was lowered onto, handed
    ;; over by the engine (provider-state-id-k9). It is the parent of every
    ;; prefix state minted below and their up-edge target — the reason the
    ;; calling convention has an argument at all.
    ;;
    ;; **This runs on the dispatch path.** Every come-to-rest re-runs it — a
    ;; cyclic `'next 'self` re-arm included — so each press of a repeatable op
    ;; pays the whole pipeline synchronously, before the next key is handled.
    ;; Measured at ~34ms on an 11-window strip in a RELEASE build (14ms
    ;; subprocess spawn, 13ms window enumeration, 5ms parse, 2ms join).
    ;; Re-measure with `-c release` or the interpreted stages inflate 2-5x and
    ;; the JSON read looks like the dominant term when it is the smallest.
    ;;
    ;; ~34ms per DELIBERATE press is not what rules `'next 'self` out — leaving
    ;; and re-entering the screen runs this same provider, so it costs the same
    ;; and two more keystrokes. The tail is: the enumeration ranges 8-29ms warm
    ;; and past 200ms cold, and KeyboardCapture filters no auto-repeat, so a
    ;; HELD op queues work faster than it drains. The reference composition
    ;; therefore ships without `'next 'self`; the full table, the ruling and
    ;; the method are in docs/specs/paneru-window-management.md decision 4.
    (define (strip-provider . opts)
      (let* ((alist       (apply props->alist opts))
             (single      (alist-ref alist 'single-alphabet '()))
             (leaders     (alist-ref alist 'leader-alphabet '()))
             (seconds     (alist-ref alist 'second-alphabet '()))
             (panel-label (alist-ref alist 'panel-label ""))
             (enumerate   (alist-ref alist 'enumerate list-current-space-windows)))
        (lambda (owner-id)
          (let* ((targets  (join-strip-targets
                             (parse-strip-windows (query-strip-state))
                             (enumerate)))
                 (assigned (jump-labels-assign targets single leaders seconds)))
            (set-current-strip-assigned! assigned)
            (strip-provider-result assigned owner-id panel-label)))))

    ;; ─── The listing block ──────────────────────────────────────────
    ;;
    ;; The un-narrowed panel's block, closed over the **Strip snapshot** so it
    ;; ALWAYS renders the exact assignment strip-provider took this Visit —
    ;; never re-querying, so the rows and the live labels cannot disagree.
    ;; The user drops it into a panel of their paneru screen.
    (define (strip-listing)
      (make-paneru-strip-block 'assigned-fn (lambda () *current-strip-assigned*)))))
