;; (modaliser muxes herdr) — herdr mux backend behind the (modaliser
;; terminal) façade. herdr (herdr.dev) is an "agent multiplexer that lives
;; in the terminal": a client/server TUI run *inside* a host terminal (the
;; user runs it in iTerm), controlled through a JSON socket-API CLI
;; (`herdr pane …`) rather than keystrokes/AppleScript.
;;
;; Quick start (prefix-style import — recommended to avoid collisions with
;; peer backend modules and the façade):
;;
;;   (import (prefix (modaliser muxes herdr) herdr:))
;;   (herdr:register!)
;;
;; Once iTerm's host backend is also registered, ops dispatch through
;; (modaliser terminal): when the focused iTerm pane's foreground command
;; is "herdr", `(terminal:focus-pane-left)` resolves to this backend's
;; `herdr pane focus --direction left`.
;;
;; ── Detection, validated live against a herdr-in-iTerm client (leaf 2) ──
;;   #1 An iTerm pane running the herdr *client* reports tty foreground
;;      command "herdr" (verified: the client is the `herdr` binary running
;;      as a foreground TUI). So the façade's mux match-key "herdr"
;;      resolves it — no special detection path needed.
;;   #2/#3 The socket API scopes per *session* (one default session = one
;;      socket) with GLOBAL focus, NOT per client / tty. `herdr pane
;;      current` answers from server state and reflects the sole client's
;;      focused pane (verified: it answers even with no client attached).
;;      Two herdr clients attached to one session therefore share one
;;      global focus and cannot be disambiguated — a documented v1
;;      non-goal; the common single-client case is unambiguous. No tty
;;      correlation (cf. tmux/zellij) is required.
;;
;; ── JSON ──
;; herdr emits compact single-line nested JSON
;; ({"id":…,"result":{…},"type":…}). The multiline awk parsers used by
;; tmux/zellij do not transfer, so we parse with (modaliser json) — a
;; small portable reader (no host JSON primitive, stays in the portable
;; tree). `herdr-json` shells out, parses, and returns the alist/vector
;; tree; a `guard` degrades any non-JSON line to #f rather than breaking a
;; leader press.
;;
;; ── Op recipes (from `herdr pane --help`) ──
;;   focus  → `pane focus  --direction <dir> --current`
;;   move   → `pane swap   --direction <dir> --current`   (swap w/ neighbour)
;;   split  → `pane split  --current --direction right|down --focus` native;
;;            LEFT/UP have no native direction, so split the opposite
;;            native way with --focus (the new pane becomes --current
;;            atomically, server-side) then `pane swap` it back toward the
;;            requested side — no split/swap focus race (R7).
;;   zoom   → `pane zoom   --current --toggle`
;;
;; ── Digit-jump focus ──
;; herdr has no dedicated "focus pane <id>" verb, but `herdr agent focus
;; <pane_id>` is a UNIVERSAL pane focus: it focuses ANY pane by id (verified
;; live cross-tab). On a bare shell pane it also emits a cosmetic
;; agent_not_found, but the focus side-effect fires first so the pane still
;; lands focused (2>/dev/null swallows the error). Digit-jump therefore
;; focuses via `agent focus <pane_id>` for every pane. The panes list block
;; (build-herdr-tree's Panes panel) paints digit CHIPS over the on-screen
;; herdr panes — see (modaliser blocks herdr-list). The backend's own
;; focus-pane-by-digit slot below (the generic-capability-tree entry point,
;; not on the shipping herdr entry-point tree) stays chip-less.
;;
;; ── Prev/Next ring cycling ([ / ]) ──
;; `[` prev / `]` next cycle the Panes/Tabs/Spaces/Agents drills'
;; DISPLAYED rows (Worktrees excluded — prev-next-nav-k4), mirroring
;; herdr's own cycle semantics. Pure computation over the live-list
;; block's already-snapshotted targets + focused-row index — same
;; "zero new herdr queries" shape as digit-jump above, wrapping at both
;; ends, firing the same focus verb the digit path uses. See
;; cycle-target-id below.

(define-library (modaliser muxes herdr)
  (export register!
          backend
          ;; herdr-in-iTerm entry-point wiring (ADR-0013): the herdr tree
          ;; builder the config splices into the herdr entry-point screen it
          ;; registers, detection-gated on (terminal:in-chain? 'herdr) — see
          ;; state-machine.sld's register-tree-up-edge!/
          ;; register-tree-entry-gated!.
          build-herdr-tree
          ;; Pure round-robin ring helper (parsed `agent list` + focused
          ;; pane_id → next blocked pane_id | #f), exported for unit tests —
          ;; the jump-to-blocked op (`b`) is a thin shell around it.
          next-blocked-pane-id
          ;; Pure prev/next ring-step helper (a live-list block's targets +
          ;; focused-row index + step → target id | #f), exported for unit
          ;; tests (prev-next-nav-k4) — the `[`/`]` keys in the Panes / Tabs
          ;; / Spaces / Agents drills are a thin shell around it.
          cycle-target-id
          ;; Pure worktree switch-target parser (k14's tagged "ws:<id>" /
          ;; "br:<branch>" target + focused source workspace id → herdr command
          ;; args | #f), exported for unit tests — the smart-switch focus-fn
          ;; behind the `W` Worktrees digit range is a thin shell around it.
          worktree-switch-command
          ;; Jump-target gathering (jump-target-gathering-k25): pure
          ;; functions turning the jump space's four raw axis inputs into
          ;; target lists. jump-pane-target-ids reads the panes axis
          ;; (parsed `pane list` JSON, tab-scoped); parse-ui-layout reads
          ;; the other three (a parsed `ui.layout` response →
          ;; workspaces/agents/tabs id lists); gather-jump-targets merges
          ;; all four into ONE list in stable-axis order (spaces → agents →
          ;; tabs → panes, jump-label-axis-pools-k43), no same-destination
          ;; dedupe (include-focused-targets-for-stability-k39) — a pure,
          ;; independently-tested utility that herdr-jump-provider (below)
          ;; no longer calls directly: each axis now assigns labels from
          ;; its OWN reserved letter pool, so the provider builds its four
          ;; axis target lists separately rather than merging first.
          jump-pane-target-ids
          parse-ui-layout
          gather-jump-targets
          ;; Mini-chip geometry (mini-chip-geometry-k31): the SAME
          ;; `ui.layout` response shape parse-ui-layout reads, but
          ;; extracting canvas-scaled pixel cell-rects instead of bare
          ;; ids — the geometry contract mini-chip-painting (next leaf)
          ;; feeds straight into ax-target-hints alongside jump labels,
          ;; the same (label . ((handle . #f)(x)(y)(w)(h))) shape
          ;; herdr-chip-entries (blocks/herdr-list.sld) already produces
          ;; for pane chips. One function per ui.layout-sourced axis.
          ui-layout-workspace-chip-entries
          ui-layout-agent-chip-entries
          ui-layout-tab-chip-entries
          ;; Jump dispatch wiring (jump-dispatch-wiring-k26): the herdr
          ;; entry node's live FSM 'provider — gathers this Visit's targets
          ;; (the functions above), assigns labels, and lowers them to live
          ;; edges/states (single-key direct, two-key narrowing prefix
          ;; states). Wired onto the tree's root via 'provider on the
          ;; config's (screen 'com.googlecode.iterm2/herdr …) call.
          herdr-jump-provider
          ;; Test seam, mirroring current-herdr-query-runner/current-herdr-
          ;; async-runner below (feedback_no_live_env_mutation_in_tests): a
          ;; jump firing otherwise calls the real focus verb (herdr-cmd ->
          ;; run-shell), capable of reaching a live herdr session from a
          ;; test. current-herdr-jump-focus-runner overrides the (kind id)
          ;; dispatch; the real default is exactly the kind's own verb.
          current-herdr-jump-focus-runner
          ;; Full-size chip painting (full-size-chip-letter-labels-k27):
          ;; jump-targets-of-kind is the pure reshape (jump-labels-assign's
          ;; ASSIGNED list -> one KIND's subset, herdr-chip-entries' (label
          ;; . id) shape), exported for unit tests; jump-panes-chip-targets
          ;; is its panes-kind specialisation (mini-chip-painting-k32
          ;; generalised the reshape by kind — see the ui.layout-sourced
          ;; kinds below). paint-jump-chips!/clear-jump-chips! are the
          ;; herdr entry node's unconditional 'entry/'exit pair
          ;; (jump-chip-entry-cutover-k48; wired on both the root screen and
          ;; each narrowing prefix state, config's app-trees/
          ;; com.googlecode.iterm2.scm) — paint reads the
          ;; ASSIGNED list herdr-jump-provider snapshotted this Visit, so
          ;; re-entering or re-narrowing always repaints from fresh data,
          ;; never stale.
          jump-targets-of-kind
          jump-panes-chip-targets
          paint-jump-chips!
          clear-jump-chips!
          ;; Narrowing-dim chip painting (narrowing-dim-state-k30):
          ;; jump-narrow-chip-targets-of-kind is the pure split of
          ;; jump-targets-of-kind's reshaped list into the surviving
          ;; ((label . id) …) pairs under LEADER vs every other chip of
          ;; that KIND, exported for unit tests; jump-narrow-chip-targets
          ;; is its panes-kind specialisation (mini-chip-painting-k32
          ;; generalised the split by kind — the SAME leader-prefix logic
          ;; applies unchanged to workspaces/agents/tabs targets).
          ;; paint-jump-chips-narrowed! is the narrowing prefix state's own
          ;; 'entry (jump-prefix-state below), painting both groups via
          ;; herdr-paint-chip-targets!'s opts, plus the three ui.layout-
          ;; sourced kinds' mini chips via herdr-paint-ui-layout-chip-
          ;; targets! (mini-chip-painting-k32).
          jump-narrow-chip-targets-of-kind
          jump-narrow-chip-targets
          paint-jump-chips-narrowed!
          ;; The Jump legend panel (legend-panel-k44, docs/specs/herdr-
          ;; jump-navigation.md "Legend"): jump-legend-block is the config's
          ;; (screen 'com.googlecode.iterm2/herdr …) panel child, closing
          ;; (modaliser blocks herdr-jump-legend)'s 'assigned-fn over
          ;; *current-jump-assigned* so the legend reads the SAME snapshot
          ;; paint-jump-chips! does, never re-gathering/re-assigning.
          jump-legend-block
          ;; The narrowed variant (narrowed-legend-k45): narrowed-jump-
          ;; legend-block closes the SAME block constructor over a prefix
          ;; state's own (second-char . target) survivor PAIRS instead of
          ;; *current-jump-assigned* — PAIRS is already the (label . target)
          ;; shape herdr-jump-legend-rows takes, its "label" here being the
          ;; remaining second key, so the survivor legend falls out with no
          ;; new rows extractor. jump-prefix-state (below) wires it into its
          ;; own provided payload's 'renderer/'children so the SAME panel-
          ;; grid renderer that draws the root screen's Jump panel draws
          ;; this one too, exported for unit tests.
          narrowed-jump-legend-block
          ;; The four async fire-and-forget herdr ops (ADR-0014), exported for
          ;; unit tests — each is also bound into build-herdr-tree's Tabs /
          ;; Spaces / Worktrees groups.
          rename-focused-tab!
          rename-focused-workspace!
          new-worktree!
          remove-focused-worktree!
          ;; The Stop Server op (`q s`), exported for unit tests — bound into
          ;; build-herdr-tree's Quit group. Its dialog-confirm gate (ADR-0014)
          ;; is driven through the same current-dialog-runner /
          ;; current-herdr-async-runner seams as the ops above, no new seam.
          ;; Detach (`q d`) has no test seam of its own — a keystroke
          ;; emission, same trust level as the config's untested copy-mode
          ;; key — so it is not exported; only a tree-shape assertion covers
          ;; it.
          stop-server!
          ;; Test seams (ADR-0014): parameterized indirection points a test
          ;; can override so no test spawns herdr
          ;; (feedback_no_live_env_mutation_in_tests) — current-herdr-query-runner
          ;; stubs canned JSON in place of a live `herdr <query>`, mirroring
          ;; `current-frontmost-bundle-id` in (modaliser terminal);
          ;; current-herdr-async-runner captures the exact verb string in
          ;; place of firing run-shell-async.
          current-herdr-query-runner
          current-herdr-async-runner)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser util)
          (modaliser shell)
          (modaliser json)
          ;; jump-labels-assign: the parameterised prefix-free label-
          ;; assignment utility (jump-dispatch-wiring-k26's consumer).
          ;; edge / provided-state: the FSM primitives the herdr entry
          ;; node's provider builds its per-Visit edges/states from
          ;; (docs/specs/fsm-graph.md) — both portable, (modaliser fsm)
          ;; imports only (scheme base) (scheme write) (modaliser util).
          (modaliser jump-labels)
          (only (modaliser fsm) edge provided-state)
          ;; sq-escape: the one canonical POSIX single-quote escaper (ADR-0014's
          ;; (modaliser dialogs) is its home); used here for shell-safe branch-
          ;; name interpolation. dialog-confirm: the Stop Server op's confirm
          ;; gate — herdr's own CLI stops the server immediately with no
          ;; herdr-side confirm of its own, unlike worktree remove above.
          (only (modaliser dialogs) sq-escape dialog-confirm)
          ;; send-keystroke: Detach has no socket/CLI verb (it's herdr's own
          ;; client-side keybinding), so it is emitted as a keystroke into the
          ;; focused iTerm session — established portable-tree practice
          ;; (apps/*.sld: chrome.sld, iterm.sld, safari.sld).
          (modaliser input)
          ;; The three herdr live-list blocks (panes / tabs / workspaces)
          ;; share one kind-parameterised constructor; build-herdr-tree wraps
          ;; each with a hidden digit key-range whose focus action lives here
          ;; (agent focus / tab focus / workspace focus). Mirrors apps/iterm
          ;; importing (modaliser blocks iterm-panes) / iterm-tabs.
          (modaliser blocks herdr-list)
          ;; The Jump legend panel's block constructor (legend-panel-k44) —
          ;; jump-legend-block below closes it over *current-jump-assigned*.
          (modaliser blocks herdr-jump-legend)
          ;; hints-hide: clears the full-size jump chips on 'on-leave
          ;; (full-size-chip-letter-labels-k27) — the paint side reuses
          ;; herdr-list's herdr-paint-chip-targets! above, so only the
          ;; clear half needs its own import here.
          (only (modaliser hints) hints-hide)
          ;; current-chip-theme: narrowing's whole-chip dim group reuses
          ;; the 'dim variant's resolved 'background BOTH as that group's
          ;; theme AND, doubled, as the surviving group's consumed-char
          ;; text colour (narrowing-dim-state-k30) — see
          ;; paint-jump-chips-narrowed! below.
          (only (modaliser theming) current-chip-theme)
          ;; The façade exports the 14 op names plus the predicates; this
          ;; module defines its own focus-pane-left etc. as record fields,
          ;; so import only the machinery we need. herdr's global-focus
          ;; socket API needs no tty correlation, so unlike zellij we do
          ;; not import correlate-mux-client-to-host-tty.
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!
                modaliser-tool-path
                ;; note-backend-query-result!: ADR-0017 Layer 2 — every
                ;; query's success/failure feeds the shared backend-health
                ;; table, so a #f here can trigger the lazily-memoized
                ;; re-probe (see herdr-json below).
                note-backend-query-result!))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where herdr lives), so every
    ;; shell-out is prefixed with the tool path — same pattern as tmux,
    ;; zellij, and the nvim helpers in (modaliser terminal).
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Socket-API query ───────────────────────────────────────────
    ;;
    ;; Run `herdr <args>`, parse stdout as JSON, return the alist/vector
    ;; tree — or #f when the command produced nothing or non-JSON. Routed
    ;; through `current-herdr-query-runner` (mirrors `current-frontmost-
    ;; bundle-id` in (modaliser terminal)) so a test can hand back canned
    ;; JSON without a live herdr session (feedback_no_live_env_mutation_in_tests).
    ;; The `guard` in the real runner is the safety net: herdr's output is
    ;; reliably JSON (even errors are `{"error":{…}}`, which parse fine and
    ;; simply lack a "result" key), but a truncated/garbage line must not
    ;; raise through a leader press.
    (define current-herdr-query-runner
      (make-parameter
        (lambda (args)
          (let ((out (string-trim
                       (run-shell
                         (string-append path-prefix "herdr " args " 2>/dev/null")))))
            (if (string=? out "")
                #f
                (guard (e (#t #f))
                  (json-parse out)))))))

    (define (herdr-json args)
      (let ((result ((current-herdr-query-runner) args)))
        (note-backend-query-result! 'herdr (and result #t))
        result))

    ;; Fire a mutating pane op; output is ignored (2>/dev/null keeps
    ;; innocuous edge-of-layout errors out of the GUI app log).
    (define (herdr-cmd args)
      (run-shell (string-append path-prefix "herdr " args " 2>/dev/null")))

    ;; ─── Async command dispatch (ADR-0014) ───────────────────────────
    ;;
    ;; Ops whose external UI needs the user's keyboard — herdr's own rename
    ;; / worktree-create / worktree-remove prompts — must not fire through
    ;; the synchronous herdr-cmd above. Dispatch has already released modal
    ;; capture for these terminal leaves (ADR-0015), but release alone is
    ;; not enough: a synchronous run-shell blocks the Scheme thread, and a
    ;; leader press while herdr's prompt is up would then stall the
    ;; keyboard tap (ADR-0014's stalled-tap failure mode). herdr-cmd-async
    ;; fires through run-shell-async and returns immediately; the callback
    ;; only logs a non-zero exit — no continuation payload, since the
    ;; argument-gathering is herdr's UI, not Modaliser's. Routed through
    ;; `current-herdr-async-runner` so a test can capture the exact verb
    ;; string instead of shelling out (feedback_no_live_env_mutation_in_tests).
    (define current-herdr-async-runner
      (make-parameter
        (lambda (args callback)
          (run-shell-async (string-append path-prefix "herdr " args) callback))))

    (define (herdr-cmd-async args)
      ((current-herdr-async-runner) args
        (lambda (code out err)
          (when (not (eqv? code 0))
            (log "herdr: '" args "' failed (exit " code "): " err)))))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; `focused-pane-id` → the server's globally-focused pane id
    ;; ("w9:p1"). `detect-fg-command` → the innermost foreground process
    ;; name of that pane, so the façade can descend one level further
    ;; (e.g. herdr → nvim) exactly as it does through tmux/zellij; a plain
    ;; shell pane reports "zsh", which matches no mux and leaves herdr the
    ;; leaf backend.

    ;; One `pane current` read, one field out of the focused pane record.
    ;; `pane current` carries the pane's own id plus its enclosing tab_id /
    ;; workspace_id, so the close/rename ops below get their target ids from
    ;; the same query without a second shell-out.
    (define (focused-pane-field field)
      (let ((j (herdr-json "pane current")))
        (and j
             (let ((v (json-ref (json-ref (json-ref j "result") "pane") field)))
               (and (string? v) v)))))

    (define (focused-pane-id)      (focused-pane-field "pane_id"))
    (define (focused-tab-id)       (focused-pane-field "tab_id"))
    (define (focused-workspace-id) (focused-pane-field "workspace_id"))

    (define (detect-fg-command)
      (let ((j (herdr-json "pane process-info --current")))
        (and j
             (let* ((pi  (json-ref (json-ref j "result") "process_info"))
                    (fps (and pi (json-ref pi "foreground_processes"))))
               (and (vector? fps)
                    (> (vector-length fps) 0)
                    (let ((name (json-ref
                                  (vector-ref fps (- (vector-length fps) 1))
                                  "name")))
                      (and (string? name) name)))))))

    ;; ─── Op primitives ──────────────────────────────────────────────

    (define (focus-pane-left)  (herdr-cmd "pane focus --direction left --current"))
    (define (focus-pane-right) (herdr-cmd "pane focus --direction right --current"))
    (define (focus-pane-up)    (herdr-cmd "pane focus --direction up --current"))
    (define (focus-pane-down)  (herdr-cmd "pane focus --direction down --current"))

    ;; Native splits (right/down): new pane on that side, focus follows it.
    (define (split-pane-right) (herdr-cmd "pane split --current --direction right --focus"))
    (define (split-pane-down)  (herdr-cmd "pane split --current --direction down --focus"))

    ;; Left/up: no native direction. Split the opposite native way with
    ;; --focus so the new pane is the server's current pane, then swap it
    ;; toward the requested side. `--focus` makes the swap target
    ;; unambiguous (it is --current), avoiding the split/swap race R7
    ;; describes; focus rides with the pane through the swap.
    (define (split-pane-left)
      (herdr-cmd "pane split --current --direction right --focus")
      (herdr-cmd "pane swap --direction left --current"))
    (define (split-pane-up)
      (herdr-cmd "pane split --current --direction down --focus")
      (herdr-cmd "pane swap --direction up --current"))

    ;; Move = swap the focused pane with its directional neighbour.
    (define (move-pane-left)   (herdr-cmd "pane swap --direction left --current"))
    (define (move-pane-right)  (herdr-cmd "pane swap --direction right --current"))
    (define (move-pane-up)     (herdr-cmd "pane swap --direction up --current"))
    (define (move-pane-down)   (herdr-cmd "pane swap --direction down --current"))

    ;; Zoom: herdr's `--toggle` is a stateless flip.
    (define (toggle-pane-zoom) (herdr-cmd "pane zoom --current --toggle"))

    ;; Close the focused pane. `pane close` needs an explicit id (no
    ;; --current form), so resolve the focused pane first. Bound to `d` at
    ;; the herdr tree top level.
    (define (close-pane)
      (let ((pid (focused-pane-id)))
        (when pid (herdr-cmd (string-append "pane close " pid)))))

    ;; ─── Digit-jump (façade slot; chip-less) ───────────────────────
    ;;
    ;; Snapshot the pane ids at mode-enter (labels 1..0 in list order),
    ;; then focus pane N via `herdr agent focus <pane_id>`.
    ;;
    ;; `agent focus <pane_id>` is a UNIVERSAL pane focus: it focuses ANY
    ;; pane by id — verified live cross-tab against p1/p2/p3. On a
    ;; non-agent (bare shell) pane it *also* emits an `agent_not_found`
    ;; error, but the focus side-effect fires first, so the pane still
    ;; lands focused (2>/dev/null in herdr-cmd swallows the cosmetic
    ;; error). This corrects the leaf-2 assumption that it no-ops on
    ;; shell panes — it does not. No `pane neighbor` geometric walk is
    ;; needed. This façade slot (the generic-capability-tree entry point)
    ;; is chip-less; the shipping herdr entry-point tree instead uses the
    ;; panes list block, whose Panes panel paints digit chips over the
    ;; on-screen herdr panes (see (modaliser blocks herdr-list)).

    ;; Still snapshots the GLOBAL `pane list`, unlike the shipping Panes
    ;; drill's block (herdr-list-block's 'panes call above), which is
    ;; tab-scoped (pane-list-tab-local-k3). Left unscoped on purpose: this
    ;; façade slot is near-dead surface (build-herdr-tree uses the block
    ;; instead, so no shipping entry-point tree reaches this path) — not
    ;; worth threading focused-tab-id through a path nothing exercises.
    (define (list-pane-ids)
      (let ((j (herdr-json "pane list")))
        (if (not j)
            '()
            (let ((panes (json-ref (json-ref j "result") "panes")))
              (if (vector? panes)
                  (let loop ((k 0) (acc '()))
                    (if (>= k (vector-length panes))
                        (reverse acc)
                        (let ((pid (json-ref (vector-ref panes k) "pane_id")))
                          (loop (+ k 1)
                                (if (string? pid) (cons pid acc) acc)))))
                  '())))))

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Snapshot taken at mode-enter so the digit-action closures don't
    ;; reissue the JSON query at keystroke time (same pattern as tmux /
    ;; zellij *current-panes*).
    (define *current-pane-ids* '())
    (define (set-current-pane-ids! ids) (set! *current-pane-ids* ids))

    (define (focus-by-digit d)
      (let ((idx (string->number d))
            (ids *current-pane-ids*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (id (and (< zero-based (length ids))
                          (list-ref ids zero-based))))
            (when id
              (herdr-cmd (string-append "agent focus " id)))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'herdr-pane-digit
        'on-enter
        (lambda () (set-current-pane-ids! (list-pane-ids)))
        'on-leave (lambda () #f)
        (digit-range)))

    ;; ─── Jump-target gathering (jump-target-gathering-k25) ──────────
    ;;
    ;; Pure functions turning the jump space's four raw axis inputs
    ;; (docs/specs/herdr-jump-navigation.md "Jump space scope" / "Jump
    ;; labels") into target lists, visual order preserved within an axis.
    ;; Visual order needs no re-sort here: `pane list`'s JSON order is
    ;; already treated as display order throughout this file (list-pane-ids,
    ;; the live-list blocks), and ui.layout's entries are contractually
    ;; listed in visual order (docs/specs/herdr-ui-layout.md "Drawn/visible
    ;; entries only").
    ;;
    ;; gather-jump-targets merges all four into ONE list in stable-axis
    ;; order — spaces (the Spaces axis — code keeps the `workspace` stem per
    ;; the Spaces-rename decision, docs/specs/herdr-jump-navigation.md
    ;; "Spaces rename") → agents → tabs → panes, revised from the original
    ;; panes-first priority by jump-label-axis-pools-k43 (see herdr-jump-
    ;; provider below for why panes-first stopped working: a volatile
    ;; current-tab pane count must no longer shift every space/agent
    ;; label). It stays a pure, independently-tested utility, but is no
    ;; longer herdr-jump-provider's own call path: each axis now assigns
    ;; labels from its OWN reserved letter pool
    ;; (docs/specs/herdr-jump-navigation.md "Jump labels"), so the provider
    ;; builds its four axis target lists directly instead of merging first
    ;; and re-splitting by kind.

    ;; Panes axis: parsed `pane list` JSON filtered to TAB-ID, preserving
    ;; JSON order. A non-string TAB-ID degrades to unfiltered (global) —
    ;; mirrors (modaliser blocks herdr-list)'s scope-id convention — though
    ;; in practice the caller always has a real focused-tab-id whenever
    ;; herdr is reachable at all. Independent of list-pane-ids above (that
    ;; one stays deliberately unscoped — see its own header comment).
    (define (jump-pane-target-ids parsed tab-id)
      (let ((arr (and parsed (json-ref (json-ref parsed "result") "panes"))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let* ((item (vector-ref arr k))
                         (pid  (json-ref item "pane_id")))
                    (loop (+ k 1)
                          (if (and (string? pid)
                                   (or (not (string? tab-id))
                                       (equal? (json-ref item "tab_id") tab-id)))
                              (cons pid acc)
                              acc))))))))

    ;; ID-KEY of every element of the array at (json-ref PARENT ARRAY-KEY),
    ;; in JSON order. A missing PARENT, a missing/non-vector array (hidden
    ;; sidebar, absent tab bar), or a non-string id degrades to omission —
    ;; never an error (docs/specs/herdr-ui-layout.md "Sidebar modes" / "Tab
    ;; bar absence").
    (define (ui-layout-ids parent array-key id-key)
      (let ((arr (and parent (json-ref parent array-key))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let ((id (json-ref (vector-ref arr k) id-key)))
                    (loop (+ k 1) (if (string? id) (cons id acc) acc))))))))

    ;; The three ui.layout-sourced axes' id lists — workspaces (Spaces),
    ;; agents (keyed on pane_id, the join key against panes), tabs — from a
    ;; full `ui.layout` response envelope (as herdr-json would return it).
    ;; A #f/error-shaped PARSED (no ui.layout support — any error means "not
    ;; supported", docs/specs/herdr-ui-layout.md "Compatibility and
    ;; probing") degrades every axis to '(): mini-chips don't paint, but
    ;; jump keys, capitals and drills are unaffected (ADR-0016). The panes
    ;; axis needs no ui.layout at all — see jump-pane-target-ids above.
    (define (parse-ui-layout parsed)
      (let* ((result  (and parsed (json-ref parsed "result")))
             (sidebar (and result (json-ref result "sidebar")))
             (tab-bar (and result (json-ref result "tab_bar"))))
        (list (cons 'workspaces (ui-layout-ids sidebar "workspaces" "workspace_id"))
              (cons 'agents     (ui-layout-ids sidebar "agents"     "pane_id"))
              (cons 'tabs       (ui-layout-ids tab-bar "tabs"       "tab_id")))))

    ;; ─── Mini-chip geometry (mini-chip-geometry-k31) ─────────────────
    ;;
    ;; (id . cell-rect) → pixel-rect synthesis for the three ui.layout-
    ;; sourced axes, mirroring herdr-chip-entries' (blocks/herdr-list
    ;; .sld) cell→pixel scaling PATTERN — divide by the TOTAL canvas,
    ;; not a sub-region — but reading `ui.layout`'s own explicit
    ;; `canvas` field (docs/specs/herdr-ui-layout.md "Coordinate space")
    ;; rather than inferring it from `pane.layout`'s `area`: the two
    ;; response shapes differ (only `ui.layout` reports canvas
    ;; directly), so this is a parallel implementation, not shared
    ;; code. Pure over PARSED + a HOST pixel frame (a fixture in tests;
    ;; at runtime the same calibrated grid frame pane chips use —
    ;; herdr-grid-frame in blocks/herdr-list) — no painting, no live
    ;; herdr, no AX of its own.

    ;; ui-layout-canvas ((result.canvas) → (width . height) or #f) is
    ;; imported from (modaliser blocks herdr-list) — relocated there by
    ;; herdr-canvas-pixel-calibration-k42 so its ui.layout paint path can
    ;; read the canvas for grid calibration (this library imports
    ;; herdr-list, so the shared accessor lives on the lower layer).

    ;; Every entry's ID-KEY → its `rect` as (x y width height), from the
    ;; array at (PARENT ARRAY-KEY). Mirrors ui-layout-ids' traversal but
    ;; keeps the rect instead of discarding it; an entry missing a
    ;; well-formed rect (or PARENT/array absent — hidden sidebar,
    ;; absent tab bar) is dropped rather than raising, same convention
    ;; as herdr-list's herdr-layout-rects.
    (define (ui-layout-section-rects parent array-key id-key)
      (let ((arr (and parent (json-ref parent array-key))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let* ((item (vector-ref arr k))
                         (id   (json-ref item id-key))
                         (r    (json-ref item "rect"))
                         (rx (and r (json-ref r "x")))
                         (ry (and r (json-ref r "y")))
                         (rw (and r (json-ref r "width")))
                         (rh (and r (json-ref r "height"))))
                    (loop (+ k 1)
                          (if (and (string? id) (number? rx) (number? ry)
                                   (number? rw) (number? rh))
                              (cons (cons id (list rx ry rw rh)) acc)
                              acc))))))))

    ;; (TARGETS ((label . id) …) — same shape herdr-chip-entries'
    ;; targets take, PARSED a full `ui.layout` response envelope as
    ;; herdr-json would return it, SECTION-KEY/ARRAY-KEY/ID-KEY
    ;; selecting one axis (see the three named wrappers below), HOST
    ;; the pixel frame alist ((x)(y)(w)(h))) → labelled chip entries,
    ;; the SAME (label . ((handle . #f)(x)(y)(w)(h))) shape
    ;; ax-target-hints already consumes. #f/malformed canvas, no host,
    ;; or a target absent from this response (scrolled away, folded,
    ;; hidden sidebar/tab bar — never an error per
    ;; docs/specs/herdr-ui-layout.md "Sidebar modes"/"Tab bar absence")
    ;; degrades that entry — or the whole call — to empty rather than
    ;; raising.
    (define (ui-layout-chip-entries targets parsed section-key array-key id-key host)
      (let ((canvas (ui-layout-canvas parsed)))
        (if (not (and canvas host))
            '()
            (let* ((result  (json-ref parsed "result"))
                   (parent  (json-ref result section-key))
                   (rects   (ui-layout-section-rects parent array-key id-key))
                   (total-w (car canvas)) (total-h (cdr canvas))
                   (hx (cdr (assoc 'x host))) (hy (cdr (assoc 'y host)))
                   (hw (cdr (assoc 'w host))) (hh (cdr (assoc 'h host))))
              (let loop ((ts targets) (acc '()))
                (cond
                  ((null? ts) (reverse acc))
                  (else
                   (let* ((label (car (car ts)))
                          (id    (cdr (car ts)))
                          (p     (assoc id rects))
                          (r     (and p (cdr p))))
                     (if r
                         (let* ((rx (list-ref r 0)) (ry (list-ref r 1))
                                (rw (list-ref r 2)) (rh (list-ref r 3))
                                ;; Round BOTH edges of the cell span, derive
                                ;; size as their difference — see
                                ;; herdr-chip-entries' matching comment in
                                ;; (modaliser blocks herdr-list) for why.
                                (x1 (+ hx (round-div (* rx hw) total-w)))
                                (x2 (+ hx (round-div (* (+ rx rw) hw) total-w)))
                                (y1 (+ hy (round-div (* ry hh) total-h)))
                                (y2 (+ hy (round-div (* (+ ry rh) hh) total-h)))
                                (x x1) (y y1) (w (- x2 x1)) (h (- y2 y1)))
                           (loop (cdr ts)
                                 (cons (cons label
                                             (list (cons 'handle #f)
                                                   (cons 'x x) (cons 'y y)
                                                   (cons 'w w) (cons 'h h)))
                                       acc)))
                         (loop (cdr ts) acc))))))))))

    ;; The three per-kind wrappers mini-chip-painting (next leaf) calls
    ;; directly — one per axis parse-ui-layout already knows (sidebar
    ;; workspaces/agents, tab_bar tabs).
    (define (ui-layout-workspace-chip-entries targets parsed host)
      (ui-layout-chip-entries targets parsed "sidebar" "workspaces" "workspace_id" host))
    (define (ui-layout-agent-chip-entries targets parsed host)
      (ui-layout-chip-entries targets parsed "sidebar" "agents" "pane_id" host))
    (define (ui-layout-tab-chip-entries targets parsed host)
      (ui-layout-chip-entries targets parsed "tab_bar" "tabs" "tab_id" host))

    ;; Every id in IDS tagged KIND, shaped ((kind . KIND) (id . ID)) —
    ;; enough to identify the target and dispatch its focus verb later
    ;; (jump-focus-fn, below, picks the verb per kind). Order preserved.
    (define (jump-axis-targets kind ids)
      (map (lambda (id) (list (cons 'kind kind) (cons 'id id))) ids))

    ;; The jump space's ordered target list: stable-axis order spaces →
    ;; agents → tabs → panes (jump-label-axis-pools-k43 — matches the Jump
    ;; legend's display order, docs/specs/herdr-jump-navigation.md
    ;; "Legend"). Every gathered target gets its own entry, even when two
    ;; targets across axes name the SAME underlying destination (e.g. an
    ;; agent whose pane is already listed under panes) — deliberately NOT
    ;; deduped (include-focused-targets-for-stability-k39: redundant paths
    ;; to the same location are better UX than a target silently vanishing
    ;; from the jump space, and a stable target SET keeps label assignment
    ;; stable too). Pure over its four already-ordered id-list inputs — no
    ;; re-sort, no re-query, no cross-invocation state.
    (define (gather-jump-targets pane-ids workspace-ids agent-ids tab-ids)
      (append (jump-axis-targets 'workspaces workspace-ids)
              (jump-axis-targets 'agents agent-ids)
              (jump-axis-targets 'tabs tab-ids)
              (jump-axis-targets 'panes pane-ids)))

    ;; ─── Jump dispatch wiring (jump-dispatch-wiring-k26) ─────────────
    ;;
    ;; The herdr entry node's live 'provider (dsl-provider-wiring-k24's
    ;; mechanism; docs/specs/fsm-graph.md "Runtime semantics"): on every
    ;; come-to-rest it gathers this Visit's jump targets (the functions
    ;; above), assigns labels ((modaliser jump-labels)'s jump-labels-
    ;; assign), and lowers them to live FSM edges/states — single-key
    ;; labels as direct key edges to a per-target Terminal state (fires
    ;; the target's kind-specific focus verb, then halts —
    ;; docs/specs/herdr-jump-navigation.md "Narrowing": "a jump firing is
    ;; Terminal: focus moves, the modal exits"); two-key labels group by
    ;; leader char into one provided PREFIX (resting) state per leader,
    ;; whose own edges are its second-key edges to those SAME per-target
    ;; Terminal states plus an 'up edge back to the herdr entry node
    ;; itself (backspace un-narrows).
    ;;
    ;; A provided RESTING state landed on from elsewhere begins a NEW
    ;; Visit (docs/specs/fsm-graph.md "Runtime semantics" — "different
    ;; state -> end the previous visit ... begin a new one"), which
    ;; installs THAT state's own extra-states in place of whatever the
    ;; root's provider installed — discarding the root's per-target
    ;; Terminal states. So each prefix state carries its OWN small
    ;; 'provider that re-mints exactly the Terminal states its own
    ;; second-key edges target, closing over the (second-char . target)
    ;; pairs the root's provider already computed (no repeat herdr
    ;; query — see jump-prefix-state below).
    ;;
    ;; A provided state's id that must survive as a VISIT OWNER (i.e. a
    ;; resting state, unlike the Terminal targets, which deactivate before
    ;; their id is ever consulted) has to read as root-id + "/" + its one
    ;; dispatch key — the same convention fsm-child-id uses for permanent
    ;; states (state-machine.sld) — because modal-current-path's strip-
    ;; id-prefix assumes a child's id textually starts with its parent's
    ;; id + "/" and would raise on a mismatched shape. This is also why a
    ;; provided RESTING state needed (modaliser fsm)'s fsm-resolved-
    ;; payload/fsm-resolved-up-edge (jump-dispatch-wiring-k26): the
    ;; presentation-facing façade (state-machine.sld's modal-current-node/
    ;; modal-root-node/breadcrumb derivation) used to read ONLY the
    ;; permanent graph, so a jump narrowing prefix state — the first
    ;; provided state ever to persist as a visit owner across more than
    ;; one keystroke — was invisible to it.

    ;; The herdr entry node's own FSM state id (register-tree!'s scope
    ;; string) — the narrowing prefix states' up-edge target, and where
    ;; this provider itself must be wired (via 'provider on the config's
    ;; (screen 'com.googlecode.iterm2/herdr …) call). Hardcoded, mirroring
    ;; pane-digit-register!'s 'herdr-pane-digit precedent above:
    ;; build-herdr-tree is spliced into exactly this one screen, nowhere
    ;; else.
    (define herdr-jump-scope "com.googlecode.iterm2/herdr")

    ;; The plane rule (plane-rule-capitals-k23) frees every lowercase
    ;; letter except `b` (Jump to Blocked) at the top level. `c` is ALSO
    ;; excluded here: the config splices its own Scrollback key onto this
    ;; SAME root alongside build-herdr-tree's children
    ;; (com.googlecode.iterm2.scm's herdr-copy-mode-key), and a state's
    ;; provider-supplied edges never override an already-registered static
    ;; one — fsm-step! finds the FIRST live edge matching a key, static
    ;; edges before provider-supplied ones (classify-and-snapshot appends
    ;; provider edges after static-edges) — so assigning "c" here would
    ;; silently mint an unreachable jump label instead of erroring. The
    ;; label space is the 20 home-position keys (never b/c, satisfying the
    ;; constraints above for free), PARTITIONED into three reserved,
    ;; per-axis single-key/leader pools (jump-label-axis-pools-k43,
    ;; revising the original one-pool global-priority scheme, pools since
    ;; re-anchored to the home position —
    ;; docs/specs/herdr-jump-navigation.md "Jump labels"): panes own the
    ;; right home row hjkl; (most-jumped targets, the resting navigation
    ;; position), spaces own the left home row, and agents/tabs SHARE the
    ;; top row — agents assigns
    ;; first so agent churn only ever shifts tab labels, never the reverse
    ;; (see herdr-jump-provider below for the hand-off). Each axis's pool
    ;; serves as BOTH its single-key and its leader alphabet — overflow
    ;; escalates to two-key labels led by the axis's own letters, never
    ;; borrowing another axis's pool. The second-key alphabet is shared by
    ;; every axis (a two-key label's second char cannot collide across
    ;; axes once first chars are disjoint), so it is the full 20-key union
    ;; of the three pools.
    (define herdr-jump-spaces-pool    (list "a" "s" "d" "f" "g"))
    (define herdr-jump-panes-pool     (list "h" "j" "k" "l" ";"))
    (define herdr-jump-shared-pool    (list "q" "w" "e" "r" "t" "y" "u" "i" "o" "p"))
    (define herdr-jump-second-alphabet (append herdr-jump-spaces-pool
                                               herdr-jump-panes-pool
                                               herdr-jump-shared-pool))

    ;; Per-kind focus verb — panes and agents share focus-pane-by-id (both
    ;; pane_id-keyed; "agent focus" is the universal pane focus, per the
    ;; module header above); workspaces/tabs use their own clean verbs.
    (define (jump-focus-fn kind)
      (case kind
        ((panes agents) focus-pane-by-id)
        ((workspaces)   focus-workspace-by-id)
        ((tabs)         focus-tab-by-id)
        (else (lambda (id) (if #f #f)))))

    ;; Test seam (mirrors current-herdr-query-runner/current-herdr-async-
    ;; runner's rationale below, ADR-0014 /
    ;; feedback_no_live_env_mutation_in_tests): a test drives real FSM
    ;; dispatch through modal-handle-key, so without this indirection a
    ;; passing jump-dispatch test would shell out through the REAL focus
    ;; verbs (herdr-cmd -> run-shell), capable of reaching a live herdr
    ;; session, not just this process. The real default is exactly "call
    ;; the target kind's existing focus verb".
    (define current-herdr-jump-focus-runner
      (make-parameter
        (lambda (kind id) ((jump-focus-fn kind) id))))

    (define (jump-target-kind target) (cdr (assoc 'kind target)))
    (define (jump-target-id   target) (cdr (assoc 'id   target)))

    ;; A stable, free-form provided-state id for TARGET's Terminal dispatch
    ;; state. Terminal states deactivate (fsm.sld's move-to!) before
    ;; modal-current-path ever consults a state's id shape (see the
    ;; section header), so no root-id prefix is needed here, only
    ;; collision-freedom across every live target.
    (define (jump-target-state-id kind id)
      (string-append "herdr-jump-target/" (symbol->string kind) "/" id))

    ;; The narrowing prefix state's id — root-id + "/" + leader, the
    ;; convention permanent child states use, so modal-current-path's
    ;; strip-id-prefix resolves it correctly (see the section header).
    (define (jump-prefix-state-id leader)
      (string-append herdr-jump-scope "/" leader))

    ;; One provided Terminal state per assigned target: entry fires the
    ;; kind-appropriate focus verb (through the test seam above), no
    ;; edges — Terminal, so firing it halts the engine immediately
    ;; (docs/specs/herdr-jump-navigation.md "Narrowing": "a jump firing is
    ;; Terminal: focus moves, the modal exits"). 'payload '() (an empty
    ;; alist, not the default #f): a Terminal state deactivates before
    ;; its payload is ever read for presentation, so this never actually
    ;; matters here, but it costs nothing and keeps the shape uniform
    ;; with jump-prefix-state below, where it DOES matter.
    (define (jump-terminal-state target)
      (let ((kind (jump-target-kind target)) (id (jump-target-id target)))
        (provided-state (jump-target-state-id kind id)
          'payload '()
          'entry (lambda () ((current-herdr-jump-focus-runner) kind id)))))

    ;; Merge (LEADER SECOND . TARGET) into BY-LEADER — an alist of
    ;; leader-char -> ((second . target) …), preserving first-seen leader
    ;; order and each leader's own second-key assignment order (append,
    ;; not cons — target counts are small, so O(n^2) buys ordering
    ;; simplicity over a smarter accumulator).
    (define (jump-merge-leader-group by-leader leader second target)
      (if (assoc leader by-leader)
          (map (lambda (kv)
                 (if (string=? (car kv) leader)
                     (cons leader (append (cdr kv) (list (cons second target))))
                     kv))
               by-leader)
          (append by-leader (list (cons leader (list (cons second target)))))))

    ;; One leader's provided PREFIX (resting) state: its own edges are the
    ;; second-key edges to PAIRS' targets plus the 'up edge back to the
    ;; un-narrowed top level; its own 'provider re-mints those SAME
    ;; Terminal states as this state's OWN Visit begins (see the section
    ;; header for why — a resting provided state landed on from elsewhere
    ;; discards whatever the PREVIOUS visit owner installed). 'entry/'exit
    ;; (jump-chip-entry-cutover-k48, unconditional — CONTEXT.md Action
    ;; slots) paint/clear the narrowed chips at come-to-rest, matching the
    ;; root screen's own 'entry/'exit pair (config's app-trees/
    ;; com.googlecode.iterm2.scm): a narrowing descent/return is a fresh
    ;; Visit boundary, so 'entry/'exit fire exactly there regardless of
    ;; `modal-overlay-delay` — see fsm.sld's move-to!/end-old-visit!.
    ;; Unlike the root screen's bare paint-jump-chips!, 'entry here is a
    ;; LEADER-closing lambda around paint-jump-chips-narrowed!
    ;; (narrowing-dim-state-k30) — it needs to know which leader this Visit
    ;; narrowed into to split survivors from everything else; 'exit stays
    ;; the plain clear-jump-chips! (hints-hide clears every group narrowing
    ;; paints into, not just the default one).
    ;;
    ;; 'payload carries 'renderer 'panel-grid + a 'children category
    ;; (narrowed-legend-k45): fsm-resolved-payload (fsm.sld) hands this
    ;; alist straight to state-machine.sld as modal-current-node, "so a
    ;; provided RESTING state ... must present the same way a permanent
    ;; one does" (its own doc comment) — and the overlay's panel-grid
    ;; renderer (ui/overlay.scm's panel-grid-payload-json) reads 'renderer/
    ;; 'children/'cols/'layout/'loose off WHATEVER alist modal-current-node
    ;; resolves to, with no separate static-screen lookup. So giving this
    ;; payload the exact shape `screen` lowers a registered root's payload
    ;; into — 'renderer 'panel-grid plus one 'children category built by
    ;; the SAME (panel …) constructor the config uses — draws the survivor
    ;; legend through the UNCHANGED renderer, no fsm.sld/state-machine.sld/
    ;; overlay.scm change needed. The panel wraps narrowed-jump-legend-block
    ;; closed over PAIRS, the exact (second-char . target) survivor list
    ;; this state's own second-key edges are built from above — no re-query,
    ;; no re-narrow. Deliberately no 'on-enter/'on-leave in this payload —
    ;; node-on-enter/node-on-leave (state-machine.sld) `assoc` for those
    ;; keys and find nothing, so the delayed overlay callback's
    ;; run-on-enter/run-on-leave are a no-op here (the double-fire trap:
    ;; leaving the old alist entries alongside 'entry/'exit would paint the
    ;; chips twice).
    (define (jump-prefix-state leader pairs)
      (let ((second-edges
              (map (lambda (p)
                     (edge (car p)
                       (jump-target-state-id (jump-target-kind (cdr p))
                                              (jump-target-id (cdr p)))))
                   pairs)))
        (apply provided-state (jump-prefix-state-id leader)
          'payload (list (cons 'renderer 'panel-grid)
                         (cons 'children (list (panel "Jump" (narrowed-jump-legend-block pairs)))))
          'entry (lambda () (paint-jump-chips-narrowed! leader))
          'exit clear-jump-chips!
          'provider (lambda ()
                      (list (cons 'states
                                  (map (lambda (p) (jump-terminal-state (cdr p))) pairs))))
          (edge 'up herdr-jump-scope)
          second-edges)))

    ;; Turn ASSIGNED ((label . target) …) — jump-labels-assign's output,
    ;; TARGET shaped ((kind . KIND) (id . ID)) per gather-jump-targets —
    ;; into this Visit's provider result: 'edges (one direct edge per
    ;; single-key label, one per USED leader char) and 'states (one
    ;; Terminal state per single-key target, one prefix state per leader —
    ;; see jump-prefix-state for why a leader's OWN targets' Terminal
    ;; states live in the PREFIX state's provider instead of here). An
    ;; unlabelled (#f) target — past both pools' exhaustion — is dropped,
    ;; the label pool's own documented tail.
    (define (jump-provider-result assigned)
      (let loop ((rest assigned) (edges '()) (states '()) (by-leader '()))
        (if (null? rest)
            (let ((leader-edges
                    (map (lambda (kv) (edge (car kv) (jump-prefix-state-id (car kv))))
                         by-leader))
                  (prefix-states
                    (map (lambda (kv) (jump-prefix-state (car kv) (cdr kv))) by-leader)))
              (list (cons 'edges (append edges leader-edges))
                    (cons 'states (append states prefix-states))))
            (let* ((entry (car rest)) (label (car entry)) (target (cdr entry)))
              (cond
                ((not label) (loop (cdr rest) edges states by-leader))
                ((= (string-length label) 1)
                 (loop (cdr rest)
                       (cons (edge label (jump-target-state-id (jump-target-kind target)
                                                                (jump-target-id target)))
                             edges)
                       (cons (jump-terminal-state target) states)
                       by-leader))
                (else
                 (let ((leader (substring label 0 1))
                       (second (substring label 1 (string-length label))))
                   (loop (cdr rest) edges states
                         (jump-merge-leader-group by-leader leader second target)))))))))

    ;; ─── Full-size chip painting (full-size-chip-letter-labels-k27) ──
    ;;
    ;; Paint jump-letter chips over on-screen panes, reusing the existing
    ;; digit-chip pipeline ((modaliser blocks herdr-list)'s herdr-chip-
    ;; entries/herdr-paint-chip-targets!) fed from THIS Visit's assigned
    ;; labels instead of digit labels. Wired as unconditional 'entry/'exit
    ;; (not 'provider — chip paint/clear is presentation, but an
    ;; UNGATED presentation action, CONTEXT.md "Action slots";
    ;; jump-chip-entry-cutover-k48) on both the herdr entry node itself
    ;; (config's app-trees/com.googlecode.iterm2.scm) and every narrowing
    ;; prefix state (jump-prefix-state above): a narrowing descent/return
    ;; is a fresh Visit boundary (a distinct resting state), so 'entry/
    ;; 'exit fire exactly there, immediately, regardless of
    ;; `modal-overlay-delay` — see fsm.sld's move-to!/end-old-visit!. Only
    ;; the PANES axis is painted here; the three
    ;; ui.layout-sourced axes (workspaces/agents/tabs) are mini-chip-
    ;; painting-k32's job, painted alongside this section's panes chips
    ;; below (see paint-jump-chips!/paint-jump-chips-narrowed!) via a
    ;; separate geometry pipeline (mini-chip-geometry-k31). An agent whose
    ;; pane is already on-screen still gets BOTH a panes-kind entry (its
    ;; on-screen pane chip) and its own agents-kind mini-chip
    ;; (include-focused-targets-for-stability-k39: gather-jump-targets no
    ;; longer collapses same-destination targets) — two independently
    ;; dispatchable paths to the same pane, not a double-paint of one.

    ;; This Visit's FULL assigned jump-label list — jump-labels-assign's
    ;; own ((label . target) …) shape — snapshotted by herdr-jump-provider
    ;; below so paint-jump-chips! can read it without re-running
    ;; gather+assign. Mirrors *current-pane-ids* above.
    (define *current-jump-assigned* '())
    (define (set-current-jump-assigned! assigned) (set! *current-jump-assigned* assigned))

    ;; ASSIGNED's KIND entries only, reshaped to herdr-chip-entries'
    ;; (label . id) shape (jump-labels-assign's target is a whole ((kind .
    ;; KIND) (id . ID)) alist — the opposite label/value order). An
    ;; unlabelled (#f) target is dropped, same as jump-provider-result's
    ;; own tail. Pure — fixture-tested directly, no live herdr. Generalised
    ;; by kind (mini-chip-painting-k32) so the SAME reshape serves panes
    ;; (jump-panes-chip-targets below) and the three ui.layout-sourced
    ;; kinds (workspaces/agents/tabs) alike.
    (define (jump-targets-of-kind kind assigned)
      (let loop ((rest assigned) (acc '()))
        (if (null? rest)
            (reverse acc)
            (let* ((entry (car rest)) (label (car entry)) (target (cdr entry)))
              (loop (cdr rest)
                    (if (and label (eq? (jump-target-kind target) kind))
                        (cons (cons label (jump-target-id target)) acc)
                        acc))))))

    (define (jump-panes-chip-targets assigned)
      (jump-targets-of-kind 'panes assigned))

    ;; ─── Mini-chip painting (mini-chip-painting-k32) ─────────────────
    ;;
    ;; The three ui.layout-sourced kinds mini-chip-geometry-k31 built
    ;; extractors for — paint-jump-chips!/paint-jump-chips-narrowed! below
    ;; feed each kind's jump-targets-of-kind reshape and matching extractor
    ;; into herdr-paint-ui-layout-chip-targets! (blocks/herdr-list.sld) as
    ;; ONE combined call, rather than one call per kind (see that
    ;; function's own header for why a combined call is needed, not just
    ;; tidier).

    (define mini-chip-kinds (list 'workspaces 'agents 'tabs))

    ;; kind → its ui-layout-*-chip-entries geometry function, mirroring
    ;; jump-focus-fn's kind → focus-verb table above.
    (define (mini-chip-geometry-fn kind)
      (case kind
        ((workspaces) ui-layout-workspace-chip-entries)
        ((agents)     ui-layout-agent-chip-entries)
        ((tabs)       ui-layout-tab-chip-entries)
        (else #f)))

    ;; Compact chip metrics for mini-chips (sidebar rows / tab titles):
    ;; full-size pane chips render at whatever .chip resolves to (56px
    ;; font-size by default, theming.sld/base.css) — much too large for a
    ;; single terminal row or a tab-title strip. Opt-carried (herdr-paint-
    ;; chip-entries!'s 'font-size/'padding overrides) rather than a
    ;; separate CSS theme variant: chip SIZE (full vs mini) and chip STATE
    ;; (bright vs narrowed-dim) vary independently — a mini chip must dim
    ;; exactly like a full-size one — so keeping size at the opts layer
    ;; reuses 'normal/'dim unchanged instead of needing a mini×dim product.
    ;; Doubled from the mini-chip-painting-k32 original (12/3) after live
    ;; dogfooding found them too small to read
    ;; (mini-chip-size-and-label-anchor-k38) — but this pair is now a
    ;; CEILING, not an exact size: ax-target-hints' 'anchor 'right clamps
    ;; the actual chip down to the target row's own live height when the
    ;; row is shorter than this, so a mini-chip never overflows a short
    ;; sidebar/tab row regardless of the user's terminal font size.
    (define mini-chip-font-size 24)
    (define mini-chip-padding 6)

    ;; ((targets . geometry-fn) …), one pair per mini-chip kind — the shape
    ;; herdr-paint-ui-layout-chip-targets! consumes. KIND->TARGETS picks
    ;; each kind's target list: the whole kind (paint-jump-chips!) or one
    ;; half of its narrowed survivor/dim split (paint-jump-chips-narrowed!).
    (define (mini-chip-pairs kind->targets)
      (map (lambda (kind) (cons (kind->targets kind) (mini-chip-geometry-fn kind)))
           mini-chip-kinds))

    ;; The paint/clear pair: full-brightness only, for the un-narrowed root.
    ;; Reading *current-jump-assigned* fresh on every call means re-entering
    ;; the root always repaints from this Visit's own data, never a stale
    ;; label from a previous one. Mini chips paint into their own 'mini
    ;; group, independent of panes' 'default group; absent ui.layout (every
    ;; geometry function degrading to '()) yields empty entries for every
    ;; kind, so herdr-paint-ui-layout-chip-targets! simply paints nothing —
    ;; panes chips are unaffected.
    (define (paint-jump-chips!)
      (herdr-paint-chip-targets! (jump-panes-chip-targets *current-jump-assigned*))
      (herdr-paint-ui-layout-chip-targets!
        (mini-chip-pairs (lambda (kind) (jump-targets-of-kind kind *current-jump-assigned*)))
        'group 'mini 'font-size mini-chip-font-size 'padding mini-chip-padding
        'anchor 'right))

    (define (clear-jump-chips!) (hints-hide))

    ;; ─── Narrowing-dim chip painting (narrowing-dim-state-k30) ───────
    ;;
    ;; While narrowed into LEADER's prefix state, ALL panes chips stay on
    ;; screen (docs/specs/herdr-jump-navigation.md "Narrowing") but split
    ;; two ways: the two-key targets under THIS leader survive at full
    ;; brightness with their consumed first char dimmed; every other panes
    ;; chip fades as a whole. *current-jump-assigned* still holds the
    ;; FULL list herdr-jump-provider snapshotted for the root's own Visit
    ;; (jump-prefix-state's own 'provider only re-mints Terminal states, it
    ;; never re-runs herdr-jump-provider), so no re-gather is needed here —
    ;; only a fresh split of data already in hand.

    ;; ASSIGNED's KIND entries (jump-targets-of-kind's own reshape) split
    ;; by whether their label survives under LEADER: a survivor is a
    ;; two-key label starting with LEADER (the exact pairs jump-prefix-
    ;; state minted this Visit's second-key edges from); everything else —
    ;; single-key labels and two-key labels under a DIFFERENT leader — dims.
    ;; Pure — fixture-tested directly, no live herdr. Generalised by kind
    ;; (mini-chip-painting-k32): the SAME leader-prefix split applies
    ;; unchanged to workspaces/agents/tabs targets, since it only reads the
    ;; label, never the kind, once jump-targets-of-kind has already
    ;; filtered to one kind.
    (define (jump-narrow-chip-targets-of-kind kind assigned leader)
      (let loop ((rest (jump-targets-of-kind kind assigned)) (survivors '()) (dim '()))
        (if (null? rest)
            (list (cons 'survivors (reverse survivors)) (cons 'dim (reverse dim)))
            (let* ((entry (car rest)) (label (car entry)))
              (if (and (= (string-length label) 2)
                       (string=? (substring label 0 1) leader))
                  (loop (cdr rest) (cons entry survivors) dim)
                  (loop (cdr rest) survivors (cons entry dim)))))))

    (define (jump-narrow-chip-targets assigned leader)
      (jump-narrow-chip-targets-of-kind 'panes assigned leader))

    ;; Paint both groups: survivors stay in the "default" hints-show-in
    ;; group (so a chip already on screen just restyles in place, no
    ;; flicker) at the 'normal theme with consumed 1 — their leader is
    ;; already typed, so the first char dims (ax-target-hints' 'consumed
    ;; passthrough, mini-chip-renderer-k29's per-char styling); everything
    ;; else moves to a separate 'jump-narrow-dim group at the 'dim theme
    ;; (whole background/border swap). The survivor group's dim-color
    ;; REUSES the 'dim variant's own resolved 'background — one CSS-
    ;; resolved "this part is inactive" colour, two renderings of it (see
    ;; theming.sld's chip-theme-dim). The three ui.layout-sourced kinds
    ;; mirror this exactly (mini-chip-painting-k32): their survivors stay
    ;; in the SAME 'mini group paint-jump-chips! used (restyle in place,
    ;; consumed 1), their dim entries move to 'jump-narrow-dim-mini — kept
    ;; separate from panes' two groups since a mini chip's SIZE differs
    ;; from a full-size chip's (mini-chip-font-size/mini-chip-padding), not
    ;; just its group. clear-jump-chips! (hints-hide, unconditional) clears
    ;; every group painted here together, same as it always has.
    (define (paint-jump-chips-narrowed! leader)
      (let* ((split (jump-narrow-chip-targets *current-jump-assigned* leader))
             (survivors (cdr (assoc 'survivors split)))
             (dim (cdr (assoc 'dim split)))
             (dim-color (cdr (assoc 'background (current-chip-theme 'dim))))
             (mini-splits
               (map (lambda (kind)
                      (cons kind (jump-narrow-chip-targets-of-kind
                                   kind *current-jump-assigned* leader)))
                    mini-chip-kinds)))
        (herdr-paint-chip-targets! survivors
          'group 'default 'theme 'normal 'consumed 1 'dim-color dim-color)
        (herdr-paint-chip-targets! dim
          'group 'jump-narrow-dim 'theme 'dim)
        (herdr-paint-ui-layout-chip-targets!
          (map (lambda (ks)
                 (cons (cdr (assoc 'survivors (cdr ks))) (mini-chip-geometry-fn (car ks))))
               mini-splits)
          'group 'mini 'font-size mini-chip-font-size 'padding mini-chip-padding
          'anchor 'right 'theme 'normal 'consumed 1 'dim-color dim-color)
        (herdr-paint-ui-layout-chip-targets!
          (map (lambda (ks)
                 (cons (cdr (assoc 'dim (cdr ks))) (mini-chip-geometry-fn (car ks))))
               mini-splits)
          'group 'jump-narrow-dim-mini 'anchor 'right
          'font-size mini-chip-font-size 'padding mini-chip-padding 'theme 'dim)))

    ;; The set of first characters ASSIGNED's labels actually consumed: a
    ;; single-key label consumes itself, a two-key label consumes only its
    ;; leader char (the second char always comes from the shared second-
    ;; alphabet, never an axis's own pool), and an unlabelled (#f) entry
    ;; consumes nothing. Feeds the agents→tabs pool hand-off below: tabs'
    ;; own pool is the shared pool minus whatever agents' assignment
    ;; actually used, so growing the agents axis shrinks tabs' pool by
    ;; exactly as much as it needed — never more, never less (CONTEXT.md
    ;; "Jump label": "for the shared pool, the axis after it" reassigns).
    (define (jump-label-used-firsts assigned)
      (let loop ((rest assigned) (acc '()))
        (if (null? rest)
            (reverse acc)
            (let ((label (car (car rest))))
              (loop (cdr rest)
                    (if (and label (not (member (substring label 0 1) acc)))
                        (cons (substring label 0 1) acc)
                        acc))))))

    ;; POOL with every letter in USED removed, order preserved.
    (define (jump-pool-remainder pool used)
      (filter (lambda (l) (not (member l used))) pool))

    ;; The herdr entry node's own 'provider (wired via 'provider on the
    ;; config's (screen 'com.googlecode.iterm2/herdr …) call, mirroring
    ;; `group`'s docstring in (modaliser dsl)): gather this Visit's live
    ;; jump targets across all four axes, assign each axis's labels from
    ;; its OWN reserved pool (jump-label-axis-pools-k43,
    ;; docs/specs/herdr-jump-navigation.md "Jump labels"), snapshot the
    ;; combined result (stable-axis order: spaces → agents → tabs → panes)
    ;; for paint-jump-chips! above, and lower it to FSM edges/states via
    ;; jump-provider-result above. Panes and spaces each assign from their
    ;; OWN dedicated pool, independent of everything else; agents assigns
    ;; from the shared pool first, then tabs assigns from whatever that
    ;; assignment left unused (jump-pool-remainder above) — the one place
    ;; an axis's labels depend on another axis's live count, and only in
    ;; that one direction (agents → tabs, never the reverse).
    (define (herdr-jump-provider)
      (let* ((tab-id (focused-tab-id))
             (pane-ids (jump-pane-target-ids (herdr-json "pane list") tab-id))
             (axes (parse-ui-layout (herdr-json "ui layout")))
             (workspace-targets (jump-axis-targets 'workspaces (cdr (assoc 'workspaces axes))))
             (agent-targets     (jump-axis-targets 'agents     (cdr (assoc 'agents axes))))
             (tab-targets       (jump-axis-targets 'tabs       (cdr (assoc 'tabs axes))))
             (pane-targets      (jump-axis-targets 'panes      pane-ids))
             (workspace-assigned (jump-labels-assign workspace-targets
                                                      herdr-jump-spaces-pool
                                                      herdr-jump-spaces-pool
                                                      herdr-jump-second-alphabet))
             (agent-assigned (jump-labels-assign agent-targets
                                                  herdr-jump-shared-pool
                                                  herdr-jump-shared-pool
                                                  herdr-jump-second-alphabet))
             (tab-pool (jump-pool-remainder herdr-jump-shared-pool
                                            (jump-label-used-firsts agent-assigned)))
             (tab-assigned (jump-labels-assign tab-targets tab-pool tab-pool
                                               herdr-jump-second-alphabet))
             (pane-assigned (jump-labels-assign pane-targets
                                                 herdr-jump-panes-pool
                                                 herdr-jump-panes-pool
                                                 herdr-jump-second-alphabet))
             (assigned (append workspace-assigned agent-assigned tab-assigned pane-assigned)))
        (set-current-jump-assigned! assigned)
        (jump-provider-result assigned)))

    ;; ─── Jump legend (legend-panel-k44) ──────────────────────────────
    ;;
    ;; The overlay panel listing the jump space's full label -> target-name
    ;; mapping (docs/specs/herdr-jump-navigation.md "Legend"): closes
    ;; (modaliser blocks herdr-jump-legend)'s 'assigned-fn over
    ;; *current-jump-assigned* so the legend ALWAYS reads the exact
    ;; assignment herdr-jump-provider snapshotted for this Visit — never
    ;; re-gathering/re-assigning, so it can never disagree with the painted
    ;; chips. Wired into the herdr entry node's screen as an ordinary panel
    ;; child (config's app-trees/com.googlecode.iterm2.scm), not inside
    ;; build-herdr-tree — the legend belongs to the entry node itself, not
    ;; the P/T/S/W/A drills build-herdr-tree assembles.
    (define (jump-legend-block)
      (make-herdr-jump-legend-block 'assigned-fn (lambda () *current-jump-assigned*)))

    ;; The narrowed variant (narrowed-legend-k45, docs/specs/herdr-jump-
    ;; navigation.md "Legend": "the prefix state renders its own filtered
    ;; legend: survivors only, name + remaining second key"). PAIRS is
    ;; jump-prefix-state's own ((second-char . target) …) survivor list —
    ;; already the SAME (label . target) shape herdr-jump-legend-rows
    ;; takes, its "label" here being the remaining second key rather than
    ;; a full jump label — so make-herdr-jump-legend-block needs no new
    ;; rows extractor, only a different 'assigned-fn source. No re-query,
    ;; no re-narrow: PAIRS is exactly what this Visit's second-key edges
    ;; were built from (see jump-prefix-state above).
    (define (narrowed-jump-legend-block pairs)
      (make-herdr-jump-legend-block 'assigned-fn (lambda () pairs)))

    ;; ─── herdr-in-iTerm entry-point wiring (ADR-0013) ───────────────
    ;;
    ;; Leader activation lands directly at the herdr entry node when the
    ;; focused iTerm pane runs herdr (detection-gated; no split-count
    ;; classification, no separate augment tree — backspace from the herdr
    ;; entry node walks to the plain iTerm node, which already has the full
    ;; splits/panes/tabs surface). See the config's app-trees/
    ;; com.googlecode.iterm2.scm for the register-tree-up-edge!/
    ;; register-tree-entry-gated! wiring.

    ;; ─── Tab & workspace ops ────────────────────────────────────────
    ;;
    ;; `create --focus` makes and switches to the new tab/workspace;
    ;; close/rename need the focused id, read from `pane current` (one
    ;; query yields pane_id + tab_id + workspace_id).
    ;;
    ;; NO tab-reorder op (k17, reconfirmed against herdr 0.7.1). The `tab`
    ;; CLI exposes only list · create · get · focus · rename · close, and
    ;; `tab list`/`tab get` carry a read-only `number` (display order) with
    ;; no verb to set it — `tab rename` mutates the label only. herdr *can*
    ;; reorder tabs, but only by MOUSE-DRAG in the TUI (persisted to
    ;; session.json); that primitive is deliberately NOT exposed on the
    ;; socket API / CLI (upstream ogulcancelik/herdr#770 "Add tab.reorder to
    ;; socket API + CLI", CLOSED not-planned). Driving reorder would mean
    ;; injecting mouse/keystrokes — barred by the socket-API-only charter —
    ;; so tab reorder is a v1 exclusion blocked on upstream herdr, NOT a
    ;; Move-Tab affordance in the `t` drill below (contrast `m` Move Pane,
    ;; which `pane swap` backs). Revisit if herdr exposes a tab-order verb.

    (define (new-tab)       (herdr-cmd "tab create --focus"))
    (define (new-workspace) (herdr-cmd "workspace create --focus"))

    (define (close-focused-tab)
      (let ((id (focused-tab-id)))
        (when id (herdr-cmd (string-append "tab close " id)))))
    (define (close-focused-workspace)
      (let ((id (focused-workspace-id)))
        (when id (herdr-cmd (string-append "workspace close " id)))))

    ;; herdr requires the rename label positionally (`tab rename <id>
    ;; <label>`), and prompt-on-missing-arg is unshipped herdr-repo work
    ;; with no ETA (ADR-0014, reworked at herdr-rename-prompt-ownership-k9),
    ;; so these two ops collect the label through a Modaliser-owned
    ;; chooser-prompt instead of firing bare and hitting herdr's own
    ;; usage-error exit. Look up ID's current label via `herdr <kind> list`
    ;; (the same query the live-list blocks already read) so the prompt
    ;; opens pre-filled; a failed/empty lookup degrades to "" rather than
    ;; blocking the rename.
    (define (herdr-label-for-id list-cmd list-key id-key id)
      (let* ((j (herdr-json list-cmd))
             (arr (and j (json-ref (json-ref j "result") list-key))))
        (if (not (vector? arr))
            ""
            (let loop ((k 0))
              (if (>= k (vector-length arr))
                  ""
                  (let ((item (vector-ref arr k)))
                    (if (equal? (json-ref item id-key) id)
                        (let ((lab (json-ref item "label")))
                          (if (string? lab) lab ""))
                        (loop (+ k 1)))))))))

    ;; Enter submits the edited label, sq-escaped and single-quoted exactly
    ;; like worktree-switch-command's branch-name interpolation below;
    ;; Escape cancels the prompt and never calls this continuation, so no
    ;; herdr call fires.
    (define (rename-focused-tab!)
      (let ((id (focused-tab-id)))
        (when id
          (open-chooser-prompt "Rename tab…"
            (herdr-label-for-id "tab list" "tabs" "tab_id" id)
            (lambda (label)
              (herdr-cmd-async
                (string-append "tab rename " id " '" (sq-escape label) "'")))))))
    (define (rename-focused-workspace!)
      (let ((id (focused-workspace-id)))
        (when id
          (open-chooser-prompt "Rename Space…"
            (herdr-label-for-id "workspace list" "workspaces" "workspace_id" id)
            (lambda (label)
              (herdr-cmd-async
                (string-append "workspace rename " id " '" (sq-escape label) "'")))))))

    ;; ─── Worktree ops (the `W` Worktrees drill, W1–W4) ──────────────
    ;;
    ;; All three verbs are source-repo pinned via `--workspace
    ;; <focused-workspace-id>` (read from `pane current`) rather than herdr's
    ;; implicit focused-workspace resolution — deterministic, and matches the
    ;; sibling tab/workspace ops. herdr's `worktree` CLI (0.7.1):
    ;;   worktree list   [--workspace ID] [--json]
    ;;   worktree create [--workspace ID] [--branch NAME] [--base REF] [--focus]
    ;;   worktree open   [--workspace ID] (--path P | --branch NAME) [--focus]
    ;;   worktree remove  --workspace ID [--force]

    ;; Smart-switch target parser (W4). k14 encodes each worktree row's switch
    ;; target as a tagged string it computes purely over the `worktree list`
    ;; payload (git refs cannot contain ':', so the tag split is unambiguous):
    ;;   "ws:<id>"     open worktree     → `workspace focus <id>` (clean verb)
    ;;   "br:<branch>" dormant worktree  → `worktree open --branch <branch>
    ;;                                      --focus` (opens a fresh workspace)
    ;; Returns the herdr command-args string, or #f for a malformed / empty
    ;; target (a detached-dormant worktree carries no target → never dispatched).
    ;; Pure (target + source ws-id → string | #f) so it is fixture-testable with
    ;; no live herdr; the `--workspace` pin is folded in only when SOURCE-WS-ID
    ;; is a real string (degrades to herdr's implicit resolution otherwise).
    (define (worktree-switch-command target source-ws-id)
      (and (string? target)
           (>= (string-length target) 3)
           (let ((tag  (substring target 0 3))
                 (rest (substring target 3 (string-length target))))
             (and (not (string=? rest ""))
                  (cond
                    ((string=? tag "ws:")
                     (string-append "workspace focus " rest))
                    ((string=? tag "br:")
                     (string-append
                       "worktree open"
                       (if (and (string? source-ws-id)
                                (not (string=? source-ws-id "")))
                           (string-append " --workspace " source-ws-id)
                           "")
                       " --branch '" (sq-escape rest) "' --focus"))
                    (else #f))))))

    ;; The digit focus-fn behind the worktrees list: parse k14's tagged target
    ;; against the live focused workspace, then fire — a thin shell over the
    ;; pure parser (mirrors `agent focus` / `tab focus` for the other kinds).
    (define (switch-worktree target)
      (let ((cmd (worktree-switch-command target (focused-workspace-id))))
        (when cmd (herdr-cmd cmd))))

    ;; New (`n`, W1). Guard on the focused workspace id — a #f means herdr is
    ;; unreachable, so no-op — then fire `worktree create` async with no
    ;; `--branch` (ADR-0014): herdr's own UI prompts for the branch name, not
    ;; a Modaliser dialog. `--focus` still switches to the new workspace once
    ;; herdr finishes creating it.
    (define (new-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-async (string-append "worktree create --workspace " wsid " --focus")))))

    ;; Remove (`d`, W2). Acts on the FOCUSED worktree — always a valid,
    ;; unambiguous target (the focused workspace's worktree), mirroring
    ;; close-pane/tab/workspace. NO `--force`: a dirty worktree or the main
    ;; checkout makes herdr/git refuse, no data loss. No Modaliser confirm
    ;; dialog (ADR-0014) — the remove-confirm UX is herdr-side; the safety
    ;; that survives here is the missing --force. #f ws-id → no-op.
    (define (remove-focused-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-async (string-append "worktree remove --workspace " wsid)))))

    ;; ─── Quit ops (the `Q` Quit group, D-etach / S-top server) ──────
    ;;
    ;; "Quit" unqualified is ambiguous between ending the herdr CLIENT and
    ;; the herdr SERVER (CONTEXT.md "Detach (herdr)" / "Stop (herdr
    ;; server)"), so the group names both explicitly rather than offering a
    ;; single bare Quit binding.

    ;; Detach (`d`). herdr has no socket/CLI verb for it — detach is the
    ;; client's OWN keybinding (default `prefix+q`, i.e. ctrl+b then q), so
    ;; it is emitted as a keystroke into the focused iTerm session where the
    ;; herdr client is listening, exactly like the config's Scrollback key
    ;; (herdr-copy-mode-k16, app-trees/com.googlecode.iterm2.scm) — same
    ;; prefix-then-key shape, same (modaliser input) portable-tree import.
    ;; Each send-keystroke is self-contained (ctrl is bracketed on `b`
    ;; only), so the trailing `q` carries no stray modifier.
    ;;
    ;; v1 assumption: the user runs herdr on the DEFAULT prefix (ctrl+b).
    ;; herdr exposes no CLI to query the resolved prefix; if the user
    ;; rebinds herdr's prefix, update the ctrl+b below to match (same
    ;; caveat as the Scrollback key).
    (define (detach!)
      (send-keystroke '(ctrl) "b")   ; herdr prefix
      (send-keystroke "q"))          ; detach-client

    ;; Stop Server (`s`). Ends the herdr SERVER: every pane and agent
    ;; terminates. Unlike worktree remove above (herdr-side confirm UX, no
    ;; Modaliser dialog), herdr's CLI stops the server immediately with no
    ;; confirm of its own — so this is the one herdr op that raises a
    ;; Modaliser dialog-confirm. CPS per ADR-0014: never synchronous
    ;; run-shell around a dialog. On confirm, fires the same fire-and-forget
    ;; async seam as the ops above.
    (define (stop-server!)
      (dialog-confirm
        "Stop the herdr server? Every pane and agent will terminate."
        (lambda (continue?)
          (when continue?
            (herdr-cmd-async "server stop")))
        'title "Stop herdr Server" 'ok-label "Stop" 'icon "caution"))

    ;; ─── Live-list blocks (panes / tabs / workspaces) ───────────────
    ;;
    ;; Each wraps the shared (modaliser blocks herdr-list) constructor and
    ;; bundles a hidden 1.. digit key-range whose action focuses the matching
    ;; id — panes via the universal `agent focus`, tabs/workspaces via their
    ;; clean `focus` verbs. cursor-*-fn wire the selection cursor to the
    ;; block's live targets / focused row (mirrors iterm:pane-list-block). A
    ;; digit pressed before the on-render snapshot ran re-snapshots on demand.
    ;; scope-id-fn is the optional zero-arg scope thunk (the panes and tabs
    ;; kinds each pass one — see herdr-list-block below); threaded through so
    ;; the on-demand refresh stays scoped identically to the on-render snapshot.
    ;;
    ;; The stale-kind guard (herdr-fast-key-drops-k8): current-targets is ONE
    ;; cell shared by every kind (the single-render invariant above the block
    ;; constructor), so a bare (assoc k …) can spuriously HIT — under the
    ;; SAME digit label — leftover targets from whichever OTHER kind rendered
    ;; last, e.g. the Panes list from an earlier press this session. That is
    ;; not a hypothetical: descending into a group fires the group's on-enter
    ;; / on-render synchronously ONLY when the overlay is already visible
    ;; (modal-handle-key's group? branch, state-machine.sld); a fast
    ;; leader→w→<digit> sequence types the digit before the overlay's
    ;; modal-overlay-delay (0.3s default) elapses, so this kind's on-render-fn
    ;; — and thus its snapshot! — never ran. Without the kind check, the
    ;; digit's assoc would silently accept the OTHER kind's id and fire the
    ;; wrong (often stale) target instead of refreshing. Root cause of the
    ;; "fast w <digit> doesn't work" report — not a stalled event tap (the
    ;; optimistic-capture buffer and the async-deferred catch-all in
    ;; KeyboardHandlerRegistry/KeyboardLibrary already keep every keystroke
    ;; queued in arrival order regardless of typing speed).
    (define (list-digit-range kind focus-fn scope-id-fn)
      (cons (cons 'hidden #t)
            (key-range "1.." "Item <n>"
              digit-labels
              (lambda (k)
                (let ((entry (or (and (eq? kind (herdr-list-current-kind))
                                       (assoc k (herdr-list-current-targets)))
                                 (begin
                                   (herdr-list-refresh! kind (and scope-id-fn (scope-id-fn)))
                                   (assoc k (herdr-list-current-targets))))))
                  (when entry (focus-fn (cdr entry))))))))

    ;; scope-id-fn: an optional zero-arg thunk scoping panes to the displayed
    ;; tab or tabs to the focused workspace (see (modaliser blocks herdr-list)'s
    ;; module header); #f for every other kind, which stay global by design.
    (define (herdr-list-block kind focus-fn chips? scope-id-fn)
      (append (make-herdr-list-block 'kind kind 'chips? chips?
                                      'scope-id-fn scope-id-fn)
              (list (cons 'cursor-targets-fn herdr-list-current-targets)
                    (cons 'cursor-initial-index-fn herdr-list-focused-index)
                    (cons 'block-children
                          (list (list-digit-range kind focus-fn scope-id-fn))))))

    ;; Named focus verbs, one per kind, so the `[`/`]` ring cycling below
    ;; (prev-next-nav-k4) fires EXACTLY the same command the digit path
    ;; does — no second definition to drift out of sync. `agent focus
    ;; <pane_id>` is the universal pane focus, so panes and agents (both
    ;; pane_id-keyed) share focus-pane-by-id.
    (define (focus-pane-by-id id)      (herdr-cmd (string-append "agent focus " id)))
    (define (focus-tab-by-id id)       (herdr-cmd (string-append "tab focus " id)))
    (define (focus-workspace-by-id id) (herdr-cmd (string-append "workspace focus " id)))

    ;; The panes block takes an optional 'chips? — when #t it paints digit
    ;; chips over the on-screen herdr panes (rects from `herdr pane layout`;
    ;; correct when herdr is the sole current-tab split, best-effort otherwise
    ;; — a pane-chip-pipeline geometry concern now, not a tree-model one
    ;; (ADR-0013's Consequences) — see the block header). tabs/workspaces
    ;; have no on-screen rects, so they never chip. Scoped to
    ;; the displayed tab (grove herdr-pane-group, pane-list-tab-local-k3) —
    ;; reuses focused-tab-id, the same `pane current` read the close/rename
    ;; ops rely on, so no extra query.
    (define (pane-list-block . opts)
      (let ((chips? (alist-ref (apply props->alist opts) 'chips? #f)))
        (herdr-list-block 'panes focus-pane-by-id chips? focused-tab-id)))
    ;; Scoped to the focused workspace (grove herdr-tabs-workspace-local-k3) —
    ;; reuses focused-workspace-id, the same `pane current` read the
    ;; close/rename ops above rely on, so no extra query.
    (define (tab-list-block)
      (herdr-list-block 'tabs focus-tab-by-id #f focused-workspace-id))
    (define (workspace-list-block)
      (herdr-list-block 'workspaces focus-workspace-by-id #f #f))
    ;; Agents list (D1/D7): the 'agents kind reorders status-priority
    ;; (blocked-first) and paints a status badge; digit → focus the agent's
    ;; pane by id via the universal `agent focus`. No chips (D6) — the list is
    ;; the visualization, and agents can live cross-workspace (off-screen).
    (define (agent-list-block)
      (herdr-list-block 'agents focus-pane-by-id #f #f))
    ;; Worktrees list (W3/W4): the 'worktrees kind whose digit target is a
    ;; COMPUTED tagged string (open → "ws:<id>", dormant → "br:<branch>"), so the
    ;; focus-fn is the smart-switch parser, not a bare `<x> focus`. Branch title +
    ;; ●/○ path detail; no chips (worktrees have no on-screen rect — the list is
    ;; the visualization, like agents).
    (define (worktree-list-block)
      (herdr-list-block 'worktrees switch-worktree #f #f))

    ;; ─── Jump to next blocked agent (top-level `b`, D4/D5) ──────────
    ;;
    ;; Round-robin over blocked agents, keyed on CURRENT FOCUS with no stored
    ;; cursor (stateless, not a Walk — D4). `next-blocked-pane-id` is pure
    ;; (parsed `agent list` + focused pane_id → next blocked pane_id | #f) and
    ;; exported for fixture tests; the op below is a thin shell that reads the
    ;; live list + focus, then focuses the target or — zero blocked — pops a
    ;; herdr toast with no focus change (D5).

    ;; Smallest string in STRS by string<?, or #f when empty. Picks the ring's
    ;; next element without a full sort — LispKit ships no stable list-sort
    ;; (see (modaliser blocks herdr-list)).
    (define (min-string strs)
      (if (null? strs)
          #f
          (let loop ((rest (cdr strs)) (m (car strs)))
            (if (null? rest)
                m
                (loop (cdr rest)
                      (if (string<? (car rest) m) (car rest) m))))))

    ;; Blocked pane_ids from a parsed `agent list` (agent_status == "blocked"),
    ;; in JSON order. #f / malformed parse → '() (the notification path).
    (define (blocked-pane-ids parsed)
      (let ((arr (and parsed
                      (json-ref (json-ref parsed "result") "agents"))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let* ((item (vector-ref arr k))
                         (st   (json-ref item "agent_status"))
                         (pid  (json-ref item "pane_id")))
                    (loop (+ k 1)
                          (if (and (equal? st "blocked") (string? pid))
                              (cons pid acc)
                              acc))))))))

    ;; The ring: the smallest blocked pane_id sorting strictly AFTER
    ;; FOCUSED-PANE-ID (round-robin's next), wrapping to the smallest overall
    ;; when focus is at/after the last blocked pane (or unknown / #f). #f when
    ;; nothing is blocked. pane_id compare is lexical ("p10" < "p2") —
    ;; acceptable for v1 while ids share a width; numeric-aware ordering
    ;; deferred (noted so a later id widening doesn't surprise).
    (define (next-blocked-pane-id parsed focused-pane-id)
      (let ((blocked (blocked-pane-ids parsed)))
        (if (null? blocked)
            #f
            (let ((after (if (string? focused-pane-id)
                             (filter (lambda (p) (string<? focused-pane-id p))
                                     blocked)
                             '())))
              (if (pair? after)
                  (min-string after)
                  (min-string blocked))))))

    ;; The op bound to `b`: focus the next blocked agent (server-wide, D2), or
    ;; toast when none. A plain key (Terminal, not a Walk) so the overlay
    ;; dismisses and the user interacts with the agent immediately (D4).
    (define (jump-to-next-blocked)
      (let ((target (next-blocked-pane-id (herdr-json "agent list")
                                          (focused-pane-id))))
        (if target
            (herdr-cmd (string-append "agent focus " target))
            (herdr-cmd "notification show 'No blocked agents'"))))

    ;; ─── Prev/Next ring cycling ([ / ], prev-next-nav-k4) ───────────
    ;;
    ;; `[` prev / `]` next cycle a drill's DISPLAYED rows one step —
    ;; mirroring herdr's own cycle semantics (prefix+n/p tabs, navigate-
    ;; mode workspaces, prefix+Tab panes; agents default to the displayed
    ;; status-banded order, no herdr binding of its own). Pure computation
    ;; over the live-list block's already-snapshotted targets + focused-
    ;; row index — the same shape as next-blocked-pane-id above, but ring-
    ;; stepped by POSITION (these targets are display-ordered, not a
    ;; sortable id) rather than searched by string order.

    ;; (cycle-target-id targets focused-index step) → target id | #f
    ;;
    ;; TARGETS is a live-list block's ((label . id) …) snapshot
    ;; (herdr-list-current-targets, display order); FOCUSED-INDEX is the
    ;; row index of the currently-focused row (herdr-list-focused-index);
    ;; STEP is +1 (next) or -1 (prev) — mirrors modal-list-cursor-move!'s
    ;; j/k step convention rather than a 'next/'prev symbol, so it never
    ;; reads as the unrelated DSL 'next-edge keyword. Ring semantics: wraps
    ;; at both ends via `modulo`. A FOCUSED-INDEX outside [0, length
    ;; TARGETS) — including #f, no row focused yet (e.g. before the first
    ;; render) — seeds the ring instead of erroring: STEP > 0 starts at the
    ;; first target, STEP < 0 at the last. Empty TARGETS → #f, the
    ;; nothing-to-cycle-to case (mirrors next-blocked-pane-id's empty-ring
    ;; #f).
    (define (cycle-target-id targets focused-index step)
      (let ((n (length targets)))
        (if (= n 0)
            #f
            (let ((idx (if (and (integer? focused-index)
                                 (>= focused-index 0)
                                 (< focused-index n))
                           (modulo (+ focused-index step) n)
                           (if (> step 0) 0 (- n 1)))))
              (cdr (list-ref targets idx))))))

    ;; The `[`/`]` press's action: ensure a fresh snapshot for THIS kind —
    ;; the same stale-kind guard list-digit-range uses above
    ;; (herdr-fast-key-drops-k8: a fast leader→drill→[ press can beat the
    ;; on-render snapshot) — then step the ring and fire FOCUS-FN on the
    ;; result. An empty ring is a silent no-op; either way the drill's
    ;; overlay refresh (triggered by the 'next 'self edge below) re-runs
    ;; the live list's on-render-fn, so the NEXT press reads a snapshot
    ;; reflecting whatever focus this press just set.
    (define (cycle-fire! kind focus-fn scope-id-fn step)
      (let* ((targets (if (eq? kind (herdr-list-current-kind))
                          (herdr-list-current-targets)
                          (herdr-list-refresh! kind (and scope-id-fn (scope-id-fn)))))
             (target (cycle-target-id targets (herdr-list-focused-index) step)))
        (when target (focus-fn target))))

    ;; The loose `[` Prev / `]` Next pair a drill splices in, uniform
    ;; across Panes/Tabs/Spaces/Agents (Worktrees deliberately
    ;; excluded — the human direction named four groups). Each is 'next
    ;; 'self — a cyclic edge re-arming right where the press happened, no
    ;; sub-mode to enter (unlike Move, one keystroke already tours the
    ;; ring) — so presses chain, and the walk feel (press-press-press
    ;; tours the ring with the list updating) falls out of the overlay
    ;; refresh described on cycle-fire! above.
    (define (cycle-nav kind focus-fn scope-id-fn)
      (fragment
        (key "[" "Prev" (lambda () (cycle-fire! kind focus-fn scope-id-fn -1)) 'next 'self)
        (key "]" "Next" (lambda () (cycle-fire! kind focus-fn scope-id-fn 1))  'next 'self)))

    ;; The Panes pair, reused in TWO places (see focus-mode-register! below):
    ;; the top-level Panes drill AND the registered herdr-panes-focus Walk,
    ;; so cycling stays available mid-focus-walk without leaving it.
    (define (pane-cycle-nav) (cycle-nav 'panes focus-pane-by-id focused-tab-id))

    ;; The Walk focus mode the Panes drill's Focus panel crosses into. The
    ;; Focus panel's hjkl each carry 'next 'herdr-panes-focus (build-herdr-
    ;; tree, a cross edge), so the first hjkl focuses AND crosses into this
    ;; mode; each member here carries 'next 'self (a cyclic edge back to
    ;; itself), so subsequent hjkl keep moving focus without another leader
    ;; press.
    ;; Also carries the `[`/`]` cycling pair (prev-next-nav-k4's "Also") —
    ;; the SAME registered Walk, not a second key-range, so a hjkl-then-[
    ;; sequence never leaves Focus mode.
    (define (focus-mode-register!)
      (register-tree! 'herdr-panes-focus
        'exit-on-unknown #t
        'display-name "Focus"
        (key "h" "Left"  focus-pane-left  'next 'self)
        (key "j" "Down"  focus-pane-down  'next 'self)
        (key "k" "Up"    focus-pane-up    'next 'self)
        (key "l" "Right" focus-pane-right 'next 'self)
        (pane-cycle-nav)))

    ;; The herdr entry-point tree (ADR-0013). Pane ops are bound to the
    ;; herdr-DIRECT ops above, never the façade, so they drive herdr
    ;; regardless of what active-backend resolves to. Returns a list of
    ;; nodes the config splices into (screen 'com.googlecode.iterm2/herdr
    ;; …) — the herdr entry point; backspace from it reaches the plain
    ;; iTerm node, which already has the full splits/panes/tabs surface,
    ;; so no separate augment tree is needed.
    ;;
    ;; Top-level keys follow the plane rule (docs/specs/herdr-jump-
    ;; navigation.md): capitals are the named drills/Quit, `b` is the one
    ;; lowercase jump kept at this level (jump-to-next-blocked is itself a
    ;; jump, not a drill), and every OTHER lowercase letter belongs to the
    ;; jump space, wired dynamically per-Visit by herdr-jump-provider
    ;; (jump-dispatch-wiring-k26) — this build-herdr-tree's static children
    ;; carry none of those edges; the config wires the provider onto this
    ;; tree's root via 'provider on its (screen 'com.googlecode.iterm2/
    ;; herdr …) call.
    ;;
    ;;   P Panes      the whole pane surface, drilled (herdr-pane-group grove):
    ;;                  Focus panel  hjkl → focus (crosses into the
    ;;                               'herdr-panes-focus Walk)
    ;;                  n New         hjkl → new split that direction
    ;;                               (left/up = split+swap)
    ;;                  m Move       Walk hjkl → swap focused pane with its
    ;;                               neighbour
    ;;                  [ / ]        Prev/Next — cycle the displayed panes
    ;;                               (tab-scoped; prev-next-nav-k4)
    ;;                  z / d        toggle zoom / close pane
    ;;                  Panes panel  the panes list + chips (digit → focus
    ;;                               by id)
    ;;   T Tabs       n/r/d + [ / ] Prev/Next (workspace-scoped) + the tabs
    ;;                list (digit → switch); no Move Tab — herdr exposes no
    ;;                socket/CLI tab-reorder verb (see Tab ops above)
    ;;   S Spaces     n/r/d + [ / ] Prev/Next (global) + the spaces list
    ;;                (digit → switch) — labelled "Spaces" throughout (herdr's
    ;;                own UI term); code identifiers keep the `workspace`
    ;;                stem (herdr's API vocabulary)
    ;;   W Worktrees  n/d + the worktrees list (digit → smart-switch); no
    ;;                [ / ] — the human direction named four cycling groups,
    ;;                not five (prev-next-nav-k4)
    ;;   b Jump       focus the next blocked agent (round-robin; toast if none)
    ;;   A Agents     [ / ] Prev/Next (status-banded order) + the agents list
    ;;                (status-badged, blocked-first; digit → focus)
    ;;   Q Quit       d Detach (keystroke, ctrl+b q) / s Stop Server (confirm-gated)
    (define (build-herdr-tree)
      (list
        (open "P" "Panes"
          (panel "Focus"
            (key "h" "Left"  focus-pane-left  'next 'herdr-panes-focus)
            (key "j" "Down"  focus-pane-down  'next 'herdr-panes-focus)
            (key "k" "Up"    focus-pane-up    'next 'herdr-panes-focus)
            (key "l" "Right" focus-pane-right 'next 'herdr-panes-focus))
          (group "n" "New"
            (key "h" "Left"  split-pane-left)
            (key "j" "Down"  split-pane-down)
            (key "k" "Up"    split-pane-up)
            (key "l" "Right" split-pane-right))
          (group "m" "Move"
            'exit-on-unknown #t
            (key "h" "Left"  move-pane-left  'next 'self)
            (key "j" "Down"  move-pane-down  'next 'self)
            (key "k" "Up"    move-pane-up    'next 'self)
            (key "l" "Right" move-pane-right 'next 'self))
          (key "z" "Zoom"  toggle-pane-zoom)
          (key "d" "Close" close-pane)
          (pane-cycle-nav)
          (panel "Panes" (pane-list-block 'chips? #t)))
        (open "T" "Tabs"
          (key "n" "New"    new-tab)
          (key "r" "Rename" rename-focused-tab!)
          (key "d" "Close"  close-focused-tab)
          (cycle-nav 'tabs focus-tab-by-id focused-workspace-id)
          (panel "Tabs" (tab-list-block)))
        (open "S" "Spaces"
          (key "n" "New"    new-workspace)
          (key "r" "Rename" rename-focused-workspace!)
          (key "d" "Close"  close-focused-workspace)
          (cycle-nav 'workspaces focus-workspace-by-id #f)
          (panel "Spaces" (workspace-list-block)))
        ;; Worktrees surface (k6). `W` drills a live worktree list: digit →
        ;; smart-switch (focus the live workspace when open, else open the
        ;; dormant worktree); `n` prompts a branch and creates one; `d`
        ;; removes the focused worktree behind a confirm (no --force). All
        ;; source-pinned via the focused workspace id.
        (open "W" "Worktrees"
          (key "n" "New"    new-worktree!)
          (key "d" "Remove" remove-focused-worktree!)
          (panel "Worktrees" (worktree-list-block)))
        ;; Agents surface (k5). `b` jumps to the next blocked agent in one
        ;; keystroke (the differentiator); `A` drills into the Agents live-list
        ;; (status-badged, blocked-first, digit → focus by id), plus [ / ]
        ;; Prev/Next over that same displayed (status-banded) order
        ;; (prev-next-nav-k4). v1 focus-only (D8) — no send/read/explain, so
        ;; the drill is the list panel plus the cycling pair.
        (key "b" "Jump to Blocked" jump-to-next-blocked)
        (open "A" "Agents"
          (cycle-nav 'agents focus-pane-by-id #f)
          (panel "Agents" (agent-list-block)))
        ;; Quit group (k2). "Quit" unqualified is ambiguous between ending
        ;; the herdr client and the herdr server (CONTEXT.md), so the group
        ;; names both ops explicitly — no bare top-level Quit binding, and a
        ;; fumbled double-tap of `Q` lands nowhere.
        (group "Q" "Quit"
          (key "d" "Detach"      detach!)
          (key "s" "Stop Server" stop-server!))))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — herdr has no provisioning step (no
    ;; config-file edits, no keybinding install); its socket-API CLI works
    ;; out of the box, earning herdr the full 14/14 surface like tmux and
    ;; zellij.
    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'herdr "herdr" 'mux "herdr" "herdr"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        'herdr-pane-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode + the Walk top-level
    ;; focus mode the herdr tree crosses into. Safe to call more than once:
    ;; register-backend! is last-write-wins on backend symbol; register-tree!
    ;; replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!)
      (focus-mode-register!))))
