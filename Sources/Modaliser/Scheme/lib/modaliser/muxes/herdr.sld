;; (modaliser muxes herdr) — herdr mux backend behind the (modaliser
;; terminal) façade. herdr (herdr.dev) is an "agent multiplexer that lives
;; in the terminal": a client/server TUI run *inside* a host terminal (the
;; user runs it in iTerm), driven over its JSON-RPC Unix socket
;; (ADR-0020) rather than keystrokes/AppleScript.
;;
;; Quick start (prefix-style import — recommended to avoid collisions with
;; peer backend modules and the façade):
;;
;;   (import (prefix (modaliser muxes herdr) herdr:))
;;   (terminal-contexts (herdr:wiring))
;;
;; That is the WIRING half only — the backend record, the context-map
;; entry, the digit-jump tree. The herdr SCREEN (which ops are surfaced,
;; on which keys, under which labels) is configuration, not facility
;; (ADR-0021): it lives in the user's config.scm as a (screen 'herdr …)
;; built from the ops this library exports, and default-config.scm ships
;; the stock composition to read and edit.
;;
;; Once iTerm's host backend is also registered, ops dispatch through
;; (modaliser terminal): when the focused iTerm pane's foreground command
;; is "herdr", `(terminal:focus-pane-left)` resolves to this backend's
;; `pane.focus_direction {direction:"left"}`.
;;
;; ── Detection, validated live against a herdr-in-iTerm client (leaf 2) ──
;;   #1 An iTerm pane running the herdr *client* reports tty foreground
;;      command "herdr" (verified: the client is the `herdr` binary running
;;      as a foreground TUI). So the façade's mux match-key "herdr"
;;      resolves it — no special detection path needed.
;;   #2/#3 The socket scopes per *session* (one default session = one
;;      socket) with GLOBAL focus, NOT per client / tty. `pane.current`
;;      answers from server state and reflects the sole client's
;;      focused pane (verified: it answers even with no client attached).
;;      Two herdr clients attached to one session therefore share one
;;      global focus and cannot be disambiguated — a documented v1
;;      non-goal; the common single-client case is unambiguous. No tty
;;      correlation (cf. tmux/zellij) is required.
;;
;; ── JSON ──
;; herdr answers with compact single-line nested JSON
;; ({"id":…,"result":{…},"type":…}) — the socket reply and the CLI's
;; printed output are the same document. The multiline awk parsers used by
;; tmux/zellij do not transfer, so we parse with (modaliser json) — a
;; small portable reader (no host JSON primitive, stays in the portable
;; tree). `herdr-query` — the ONE read seam, shared with the herdr blocks,
;; see (modaliser muxes herdr-socket) — returns the parsed envelope, or #f
;; for every failure (unreachable socket, timeout, unparseable reply,
;; structured error) rather than breaking a leader press.
;;
;; ── Op recipes (methods, cross-checked against `herdr api schema --json`) ──
;;   focus  → `pane.focus_direction {direction}`
;;   move   → `pane.swap  {direction}`                    (swap w/ neighbour)
;;   split  → `pane.split {direction:"right"|"down", focus:#t}` native;
;;            LEFT/UP have no native direction, so split the opposite
;;            native way with focus (the new pane becomes current
;;            atomically, server-side) then `pane.swap` it back toward the
;;            requested side — no split/swap focus race (R7).
;;   zoom   → `pane.zoom  {mode:"toggle"}`
;;
;; `move` there is a pane SWAP with a neighbour — positional, no index. The
;; unrelated tab/space REORDER (`tab.move` / `workspace.move`, an absolute
;; `insert_index`) is the `m` Move group in the T / S drills; see the Reorder
;; section below, which is where the index model is settled.
;;
;; ── Digit-jump focus ──
;; `pane.focus {pane_id}` is the universal by-id focus: it focuses ANY pane,
;; agent-hosting or not. Its narrower cousin `agent.focus {target}` resolves
;; only panes currently hosting an agent, and that narrowness WAS the
;; pane-switching regression (ADR-0020) — the CLI era routed digit-jump
;; through it and lost every plain-shell pane to an `agent_not_found` that
;; `2>/dev/null` then swallowed. `agent.focus` has no caller left in this
;; backend. The panes list block paints digit CHIPS over the on-screen
;; herdr panes — see (modaliser blocks herdr-list). The backend's own
;; focus-pane-by-digit slot below (the generic-capability-tree entry
;; point, not the herdr screen a config authors) stays chip-less.
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
  (export backend
          ;; ── The wiring fragment (ADR-0018 / ADR-0021) ──────────────
          ;;
          ;; Everything herdr's integration needs and nothing a user would
          ;; want to choose: the Terminal-context-map entry, the backend
          ;; record, and the machinery-named digit-jump tree the record
          ;; fires at. It authors no key and no label, so composing herdr
          ;; into ANY terminal-like host is one call:
          ;;
          ;;   (terminal-contexts (herdr:wiring))
          ;;
          ;; The herdr SCREEN — which of the ops below are surfaced, on
          ;; which keys, under which labels, in which drills — is
          ;; configuration, not facility (ADR-0021), so it lives in the
          ;; user's own config.scm as a (screen 'herdr …); the seeded
          ;; default-config.scm carries the stock composition to read and
          ;; edit. The scope symbol is machinery-named, not a preference:
          ;; the context entry below references the 'herdr tree BY KEY, so
          ;; a screen authored under any other scope is a load-time
          ;; closure error rather than a silent no-op. The same holds for
          ;; 'herdr-panes-focus, which the config's Focus rows cross into.
          wiring
          ;; herdr's stock client keybinding prefix as one named value —
          ;; a FACT about herdr, so it stays here, while whether the user
          ;; overrode it is a decision their config makes by passing a
          ;; different (mods key) list to the three keystroke ops below.
          ;; herdr exposes no way to query the resolved prefix, so this is
          ;; an assumption stated once rather than a reading; the same
          ;; unqueryable-default applies one level down, to each op's
          ;; SECOND keystroke (`[`, `e`, `q`), which is why they are
          ;; separate ops a config can replace individually.
          herdr-default-prefix
          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;;
          ;; One name per thing herdr can do. These are the stable layer —
          ;; `focus-pane-left`'s definition has changed twice in its life
          ;; (birth, and the socket cutover) behind an unchanged name and
          ;; signature — which is why the exported surface is at op grain
          ;; rather than at the whole-drill constructors that churned.
          ;; Zero-argument ops are bound directly, `(key "z" "Zoom"
          ;; herdr:toggle-pane-zoom)`; the by-id verbs and the three
          ;; keystroke constructors take arguments (see below).
          focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
          split-pane-left  split-pane-right  split-pane-up    split-pane-down
          move-pane-left   move-pane-right   move-pane-up     move-pane-down
          toggle-pane-zoom close-pane
          new-tab       close-focused-tab       rename-focused-tab!
          new-workspace close-focused-workspace rename-focused-workspace!
          jump-to-next-blocked
          ;; The by-id focus verbs and the two focused-scope readers, the
          ;; pieces a `[`/`]` cycling pair or a hand-rolled list binding
          ;; composes from: a focus-fn plus the zero-arg scope thunk that
          ;; keeps the ring scoped the way the matching list block is
          ;; (panes → the displayed tab, tabs → the focused workspace,
          ;; workspaces/agents → global, i.e. #f).
          focus-pane-by-id focus-tab-by-id focus-workspace-by-id
          focused-tab-id   focused-workspace-id
          ;; The `[` Prev / `]` Next ring step as two ops rather than one
          ;; key pair (the pair was a library-authored key and label, and
          ;; therefore a decision — ADR-0021). Each takes the same
          ;; (kind focus-fn scope-id-fn) triple the list blocks use and
          ;; returns a thunk; bind them on whichever keys you like, with
          ;; 'next 'self so presses chain.
          cycle-prev-op cycle-next-op
          ;; herdr's three client-side keybindings, as (prefix → thunk)
          ;; constructors: copy mode, the scrollback buffer, and detaching
          ;; the client. None has a socket or CLI verb — all three are the
          ;; herdr CLIENT's own bindings — so each emits herdr's prefix
          ;; followed by its own second key as a keystroke pair into the
          ;; frontmost app. PREFIX is a (mods key) list; herdr-default-prefix
          ;; above is the stock one.
          copy-mode-op scrollback-op detach-op
          ;; Pure round-robin ring helper (parsed `agent list` + focused
          ;; pane_id → next blocked pane_id | #f), exported for unit tests —
          ;; the jump-to-blocked op (`b`) is a thin shell around it.
          next-blocked-pane-id
          ;; ── Live-list blocks ──────────────────────────────────────
          ;;
          ;; One per herdr list kind, each a panel child that renders the
          ;; live rows AND carries a hidden 1.. digit range focusing the
          ;; matching id. Facilities: the row shape, the digit range and
          ;; the scoping are fixed by what herdr reports, not by taste —
          ;; which panel a block goes in, and whether it is surfaced at
          ;; all, is the config's call. The panes block takes an optional
          ;; 'chips? #t to paint digit chips over the on-screen panes.
          pane-list-block tab-list-block workspace-list-block
          agent-list-block worktree-list-block
          ;; Pure prev/next ring-step helper (a live-list block's targets +
          ;; focused-row index + step → target id | #f), exported for unit
          ;; tests (prev-next-nav-k4) — cycle-prev-op / cycle-next-op above
          ;; are thin shells around it.
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
          ;; config's (screen 'herdr …) call.
          herdr-jump-provider
          ;; Test seam, mirroring current-herdr-command-runner/current-herdr-
          ;; send-runner below (feedback_no_live_env_mutation_in_tests): a
          ;; jump firing otherwise calls the real focus verb (herdr-cmd ->
          ;; the socket), capable of reaching a live herdr session from a
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
          ;; herdr entry node's presentation-gated 'on-enter/'on-leave pair
          ;; (defer-chips-to-overlay-k33; the config wires them onto its
          ;; own (screen 'herdr …), and the provider's lowering wires the
          ;; same pair onto each narrowing prefix state) — paint reads the
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
          ;; 'on-enter (jump-prefix-state below), painting both groups via
          ;; herdr-paint-chip-targets!'s opts, plus the three ui.layout-
          ;; sourced kinds' mini chips via herdr-paint-ui-layout-chip-
          ;; targets! (mini-chip-painting-k32).
          jump-narrow-chip-targets-of-kind
          jump-narrow-chip-targets
          paint-jump-chips-narrowed!
          ;; The Jump legend panel (legend-panel-k44, docs/specs/herdr-
          ;; jump-navigation.md "Legend"): jump-legend-block is the config's
          ;; (screen 'herdr …) panel child, closing
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
          ;; own provided payload's 'children + 'display so the SAME panel-
          ;; grid renderer that draws the root screen's Jump panel draws
          ;; this one too, exported for unit tests.
          narrowed-jump-legend-block
          ;; The two worktree ops, sent without awaiting a reply (see the
          ;; send seam below for why they divide from the rename pair,
          ;; which are plain synchronous commands).
          new-worktree!
          remove-focused-worktree!
          ;; Reorder (herdr-tab-space-reorder-k36): the tab/space Move ops,
          ;; backed by herdr 0.7.5's `tab.move` / `workspace.move`. Two pure
          ;; functions carry the logic and are exported for unit tests, on
          ;; the cycle-target-id /
          ;; worktree-switch-command precedent — reorder-insert-index is the
          ;; relative-key → absolute-`insert_index` arithmetic (herdr's index
          ;; is a GAP into the pre-removal list, so the two directions are
          ;; NOT symmetric), and reorder-command is the whole decision over a
          ;; parsed `<kind>.list` envelope, yielding a (method . params) call
          ;; or #f for every nothing-to-do including either end of the list.
          ;; The four ops are thin shells, exported so a test can assert the
          ;; verb that actually reaches the wire (ADR-0020's altitude lesson).
          reorder-insert-index
          reorder-command
          move-tab-left move-tab-right
          move-space-up move-space-down
          ;; The Stop Server op. Its dialog-confirm gate (ADR-0014) is
          ;; driven through the same current-dialog-runner /
          ;; current-herdr-send-runner seams as the ops above, no new seam.
          ;; Its keystroke-emitting sibling detach-op has no test seam of
          ;; its own — a keystroke emission, same trust level as copy-mode-op
          ;; and scrollback-op — but it cannot be built without a prefix,
          ;; which is the property worth pinning.
          stop-server!
          ;; Test seams (ADR-0014): parameterized indirection points a test
          ;; can override so no test reaches a live herdr
          ;; (feedback_no_live_env_mutation_in_tests) —
          ;; current-herdr-command-runner captures the (method params) pair a
          ;; mutating op would put on the socket — the altitude at which
          ;; `agent focus` and `pane.focus` finally differ, hence the pinned
          ;; pane-switching regression test (ADR-0020);
          ;; current-herdr-send-runner captures the same pair for the ops
          ;; whose reply is deliberately not awaited. The READ side has no
          ;; seam here: every herdr query in the tree goes through the ONE
          ;; current-herdr-query-runner in (modaliser muxes herdr-socket).
          current-herdr-command-runner
          current-herdr-send-runner)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser json)
          ;; The socket transport (ADR-0020) — no (modaliser shell) import
          ;; remains, this backend never shells out. It lives in its own
          ;; library because (modaliser blocks herdr-list), which this file
          ;; imports, needs the same transport and would otherwise close an
          ;; import cycle (list-block-query-cutover-k32):
          ;;   herdr-query          — the shared read seam
          ;;   herdr-socket-request — the transport under the command seam
          ;;   herdr-socket-send    — its no-reply sibling, under the send seam
          (modaliser muxes herdr-socket)
          ;; jump-labels-assign: the parameterised prefix-free label-
          ;; assignment utility (jump-dispatch-wiring-k26's consumer).
          ;; edge / provided-state: the FSM primitives the herdr entry
          ;; node's provider builds its per-Visit edges/states from
          ;; (docs/specs/fsm-graph.md) — both portable, (modaliser fsm)
          ;; imports only (scheme base) (scheme write) (modaliser util).
          (modaliser jump-labels)
          (only (modaliser fsm) edge provided-state open-chooser-prompt)
          ;; dialog-confirm: the Stop Server op's confirm gate — herdr stops
          ;; the server immediately with no herdr-side confirm of its own,
          ;; unlike worktree remove. `sq-escape` left with the shell: every
          ;; user-supplied value is now a JSON string value, and `json-write`
          ;; owns escaping for all of them.
          (only (modaliser dialogs) dialog-confirm)
          ;; send-keystroke: Detach has no socket/CLI verb (it's herdr's own
          ;; client-side keybinding), so it is emitted as a keystroke into the
          ;; focused iTerm session — established portable-tree practice
          ;; (apps/*.sld: chrome.sld, iterm.sld, safari.sld).
          (modaliser input)
          ;; The herdr live-list blocks share one kind-parameterised
          ;; constructor; the per-kind wrappers below add a hidden digit
          ;; key-range whose focus action lives here (pane / tab /
          ;; workspace focus). Mirrors apps/iterm importing
          ;; (modaliser blocks iterm-panes) / iterm-tabs.
          (modaliser blocks herdr-list)
          ;; The Jump legend panel's block constructor (legend-panel-k44) —
          ;; jump-legend-block below closes it over *current-jump-assigned*.
          (modaliser blocks herdr-jump-legend)
          ;; The contribution constructors for `wiring` below —
          ;; prefixed: the bare names (context, backend, tree) collide
          ;; with this module's own vocabulary.
          (prefix (modaliser configuration) config:)
          ;; hints-hide: clears the full-size jump chips on 'on-leave
          ;; (full-size-chip-letter-labels-k27, defer-chips-to-overlay-k33)
          ;; — the paint side reuses
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
          ;; No `modaliser-tool-path` here: ADR-0017's PATH derivation is moot
          ;; for herdr now that nothing in this file spawns a process. It
          ;; stays load-bearing for the CLI-native backends (tmux, zellij).
          ;; No `note-backend-query-result!` either: herdr has left ADR-0017
          ;; Layer 2 altogether (list-block-query-cutover-k32) — see the
          ;; backend record's tool-name below.
          (only (modaliser terminal) make-terminal-backend))
  (begin

    ;; ─── Command seam ───────────────────────────────────────────────
    ;;
    ;; Fire a mutating op; the response is ignored (a failure is already
    ;; logged by the transport, and an edge-of-layout no-op is not worth
    ;; surfacing to the user).
    ;;
    ;; `current-herdr-command-runner` is a test seam in its own right, and a
    ;; load-bearing one: without it the lowest assertable altitude was
    ;; `current-herdr-jump-focus-runner`'s (kind . id) pairs, at which
    ;; `agent focus` and `pane.focus` look identical — which is how the
    ;; pane-switching regression shipped. Capturing here pins the verb that
    ;; actually reaches herdr.
    (define current-herdr-command-runner
      (make-parameter herdr-socket-request))

    (define (herdr-cmd method params)
      ((current-herdr-command-runner) method params))

    ;; ─── Send seam: the ops whose reply we must not wait for ─────────
    ;;
    ;; Three ops cannot ride `herdr-cmd` above, because their reply does not
    ;; arrive promptly — or at all — and waiting on it would block the eval
    ;; thread for the full timeout as a matter of routine, which is exactly
    ;; ADR-0014's stalled-tap hazard:
    ;;
    ;;   worktree.create / worktree.remove — herdr answers these only once a
    ;;     `git worktree add`/`remove` subprocess finishes. That is bounded,
    ;;     unlike a human, but it scales with working-tree size and can fire
    ;;     the user's own post-checkout hook.
    ;;   server.stop — the server acknowledges and then dies; whether the
    ;;     reply outruns the exit is a race we have no reason to enter.
    ;;
    ;; So they go over `herdr-socket-send`: connect, send, close, never read.
    ;; The op still happens in full — herdr does all of its work (creating
    ;; the workspace, switching focus, emitting events) BEFORE composing the
    ;; reply, and drops the reply silently if nobody is listening. What we
    ;; give up is only the acknowledgement, which no caller here consumed
    ;; even when it was available.
    ;;
    ;; This is what makes these plain calls rather than the CPS the shell-out
    ;; era needed: connect+send is sub-millisecond against a local peer, so
    ;; there is no stall to hide behind a callback, and no continuation to
    ;; thread. The ops that DO raise interactive UI keep their CPS — but that
    ;; UI is Modaliser's own (`open-chooser-prompt`, `dialog-confirm`), which
    ;; was always the case; herdr's socket API never prompts.
    ;;
    ;; Routed through `current-herdr-send-runner` so a test can capture the
    ;; (method params) pair instead of reaching a live herdr, at the same
    ;; altitude as `current-herdr-command-runner`
    ;; (feedback_no_live_env_mutation_in_tests).
    (define current-herdr-send-runner
      (make-parameter herdr-socket-send))

    (define (herdr-cmd-send method params)
      ((current-herdr-send-runner) method params))

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
      (let ((j (herdr-query "pane.current" '())))
        (and j
             (let ((v (json-ref (json-ref (json-ref j "result") "pane") field)))
               (and (string? v) v)))))

    (define (focused-pane-id)      (focused-pane-field "pane_id"))
    (define (focused-tab-id)       (focused-pane-field "tab_id"))
    (define (focused-workspace-id) (focused-pane-field "workspace_id"))

    (define (detect-fg-command)
      (let ((j (herdr-query "pane.process_info" '())))
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

    (define (focus-pane-left)  (herdr-cmd "pane.focus_direction" '(("direction" . "left"))))
    (define (focus-pane-right) (herdr-cmd "pane.focus_direction" '(("direction" . "right"))))
    (define (focus-pane-up)    (herdr-cmd "pane.focus_direction" '(("direction" . "up"))))
    (define (focus-pane-down)  (herdr-cmd "pane.focus_direction" '(("direction" . "down"))))

    ;; Native splits (right/down): new pane on that side, focus follows it.
    (define (split-pane-right) (herdr-cmd "pane.split" '(("direction" . "right") ("focus" . #t))))
    (define (split-pane-down)  (herdr-cmd "pane.split" '(("direction" . "down") ("focus" . #t))))

    ;; Left/up: no native direction. Split the opposite native way with
    ;; --focus so the new pane is the server's current pane, then swap it
    ;; toward the requested side. `--focus` makes the swap target
    ;; unambiguous (it is --current), avoiding the split/swap race R7
    ;; describes; focus rides with the pane through the swap.
    (define (split-pane-left)
      (herdr-cmd "pane.split" '(("direction" . "right") ("focus" . #t)))
      (herdr-cmd "pane.swap" '(("direction" . "left"))))
    (define (split-pane-up)
      (herdr-cmd "pane.split" '(("direction" . "down") ("focus" . #t)))
      (herdr-cmd "pane.swap" '(("direction" . "up"))))

    ;; Move = swap the focused pane with its directional neighbour.
    (define (move-pane-left)   (herdr-cmd "pane.swap" '(("direction" . "left"))))
    (define (move-pane-right)  (herdr-cmd "pane.swap" '(("direction" . "right"))))
    (define (move-pane-up)     (herdr-cmd "pane.swap" '(("direction" . "up"))))
    (define (move-pane-down)   (herdr-cmd "pane.swap" '(("direction" . "down"))))

    ;; Zoom: herdr's `--toggle` is a stateless flip.
    (define (toggle-pane-zoom) (herdr-cmd "pane.zoom" '(("mode" . "toggle"))))

    ;; Close the focused pane. `pane close` needs an explicit id (no
    ;; --current form), so resolve the focused pane first. Bound to `d` at
    ;; the herdr tree top level.
    (define (close-pane)
      (let ((pid (focused-pane-id)))
        (when pid (herdr-cmd "pane.close" (list (cons "pane_id" pid))))))

    ;; ─── Digit-jump (façade slot; chip-less) ───────────────────────
    ;;
    ;; Snapshot the pane ids at mode-enter (labels 1..0 in list order),
    ;; then focus pane N by id.
    ;;
    ;; This used to fire `agent focus <pane_id>`, on the belief that it was
    ;; a UNIVERSAL pane focus whose side-effect landed before the cosmetic
    ;; `agent_not_found`. That belief was wrong, and `2>/dev/null` hid the
    ;; evidence: in herdr 0.7.5 `agent focus` resolves ONLY agent panes, so
    ;; a bare shell or file-browser pane was never focused at all
    ;; (herdr-pane-switching-regression-k25, ADR-0020). The socket's
    ;; `pane.focus {pane_id}` is the real universal focus — it is what the
    ;; agents axis's `agent.focus {target}` is NOT — and it is what every
    ;; by-id pane focus in this file now uses.
    ;;
    ;; This façade slot (the generic-capability-tree entry point) is
    ;; chip-less; the shipping herdr entry-point tree instead uses the panes
    ;; list block, whose Panes panel paints digit chips over the on-screen
    ;; herdr panes (see (modaliser blocks herdr-list)).

    ;; Still snapshots the GLOBAL `pane list`, unlike the shipping Panes
    ;; drill's block (herdr-list-block's 'panes call above), which is
    ;; tab-scoped (pane-list-tab-local-k3). Left unscoped on purpose: this
    ;; façade slot is near-dead surface (a herdr screen binds the panes
    ;; list block instead, so no authored tree reaches this path) — not
    ;; worth threading focused-tab-id through a path nothing exercises.
    (define (list-pane-ids)
      (let ((j (herdr-query "pane.list" '())))
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
            (when id (focus-pane-by-id id))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-tree)
      (tree-root 'herdr-pane-digit
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
    ;; full `ui.layout` response envelope (as herdr-query would return it).
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
    ;; herdr-query would return it, SECTION-KEY/ARRAY-KEY/ID-KEY
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
    ;; states (fsm.sld) — because modal-current-path's strip-
    ;; id-prefix assumes a child's id textually starts with its parent's
    ;; id + "/" and would raise on a mismatched shape. This is also why a
    ;; provided RESTING state needed (modaliser fsm)'s fsm-resolved-
    ;; payload/fsm-resolved-up-edge (jump-dispatch-wiring-k26): the
    ;; presentation-facing façade (fsm.sld's modal-current-node/
    ;; modal-root-node/breadcrumb derivation) used to read ONLY the
    ;; permanent graph, so a jump narrowing prefix state — the first
    ;; provided state ever to persist as a visit owner across more than
    ;; one keystroke — was invisible to it.

    ;; The herdr entry node's own FSM state id — the config's (screen
    ;; 'herdr …) scope, the narrowing prefix states' up-edge target, and
    ;; where this provider itself is wired (via 'provider on that screen).
    ;; Hardcoded, mirroring pane-digit-tree's 'herdr-pane-digit precedent
    ;; above: the scope symbol is MACHINERY, not preference — `wiring`'s
    ;; context entry names the same 'herdr tree, so a screen authored under
    ;; another scope is a load-time closure error (ADR-0021).
    ;;
    ;; A provider is now handed its owner's id (provider-state-id-k9), which
    ;; makes this constant redundant in principle — herdr could read the
    ;; scope instead of asserting it. It is left as-is deliberately: it is
    ;; correct today, and `wiring`'s context entry pins the same 'herdr tree
    ;; either way, so the swap buys nothing this workstream needs
    ;; (docs/specs/paneru-window-management.md "Out of scope").
    (define herdr-jump-scope "herdr")

    ;; The plane rule (plane-rule-capitals-k23) frees every lowercase
    ;; letter except `b` (the stock Jump-to-Blocked key) at the top level.
    ;; `c` is ALSO excluded, and that exclusion outlives whatever a config
    ;; binds: a state's provider-supplied edges never override an
    ;; already-registered static one — fsm-step! finds the FIRST live edge
    ;; matching a key, static edges before provider-supplied ones
    ;; (classify-and-snapshot appends provider edges after static-edges) —
    ;; so a jump label that collides with a statically-bound top-level key
    ;; is silently unreachable rather than an error. `b` and `c` are the
    ;; two the stock composition binds (Jump to Blocked, Copy Mode), and
    ;; reserving them here costs nothing while a config that rebinds them
    ;; simply leaves two letters unused. Capitals need no exclusion at all:
    ;; the pools below are lowercase-only, so a capital can never collide
    ;; with a jump label by construction. The
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
    ;; pane_id-keyed, and `pane.focus` is the universal by-id pane focus —
    ;; see its definition below); workspaces/tabs use their own verbs.
    (define (jump-focus-fn kind)
      (case kind
        ((panes agents) focus-pane-by-id)
        ((workspaces)   focus-workspace-by-id)
        ((tabs)         focus-tab-by-id)
        (else (lambda (id) (if #f #f)))))

    ;; Test seam (mirrors current-herdr-command-runner/current-herdr-send-
    ;; runner's rationale above, ADR-0014 /
    ;; feedback_no_live_env_mutation_in_tests): a test drives real FSM
    ;; dispatch through modal-handle-key, so without this indirection a
    ;; passing jump-dispatch test would reach the socket through the REAL
    ;; focus verbs (herdr-cmd), touching a live herdr session, not just
    ;; this process. The real default is exactly "call the target kind's
    ;; existing focus verb".
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
    ;; discards whatever the PREVIOUS visit owner installed).
    ;; 'on-enter/'on-leave (defer-chips-to-overlay-k33, presentation-gated
    ;; — CONTEXT.md Action slots) paint/clear the narrowed chips, matching
    ;; the root screen's own 'on-enter/'on-leave pair. They live in the
    ;; PAYLOAD, not this state's own show/hide slots: the façade's
    ;; run-on-enter/run-on-leave read node-on-enter/node-on-leave off
    ;; whatever alist modal-current-node resolves to, and the engine's own
    ;; show/hide slots are never fired in production (fsm-mark-displayed!
    ;; has no host caller — see fsm.sld). Narrowing still repaints with no
    ;; perceptible delay: a narrowing descent only happens once the user has
    ;; SEEN the chips, so the overlay is already open and
    ;; fire-group-descent! runs run-on-leave/run-on-enter synchronously —
    ;; only the FIRST paint waits out `modal-overlay-delay`.
    ;; Unlike the root screen's bare paint-jump-chips!, 'on-enter here is a
    ;; LEADER-closing lambda around paint-jump-chips-narrowed!
    ;; (narrowing-dim-state-k30) — it needs to know which leader this Visit
    ;; narrowed into to split survivors from everything else; 'on-leave stays
    ;; the plain clear-jump-chips! (hints-hide clears every group narrowing
    ;; paints into, not just the default one).
    ;;
    ;; 'payload carries the two-layer node shape (narrowed-legend-k45,
    ;; readers-cutover): fsm-resolved-payload (fsm.sld) hands this alist
    ;; straight to fsm.sld as modal-current-node, "so a provided RESTING
    ;; state ... must present the same way a permanent one does" (its own
    ;; doc comment) — and the overlay's panel-grid renderer resolves
    ;; 'children + 'display off WHATEVER alist modal-current-node
    ;; resolves to (resolve-display; ADR-0011), with no separate
    ;; static-screen lookup. So giving this payload the exact shape
    ;; `screen` lowers a registered root's payload into — the legend
    ;; block as a flat dispatch child, one display panel clause
    ;; referencing it by id — draws the survivor legend through the
    ;; UNCHANGED renderer, no fsm.sld/overlay.scm change needed. The
    ;; panel wraps narrowed-jump-legend-block closed over PAIRS, the
    ;; exact (second-char . target) survivor list this state's own
    ;; second-key edges are built from above — no re-query, no
    ;; re-narrow. It also carries the chip pair above, and this state's
    ;; own 'entry/'exit slots are deliberately left unset — the
    ;; double-fire trap runs the other way now: an 'entry alongside the
    ;; payload's 'on-enter would paint the chips twice.
    (define (jump-prefix-state leader pairs)
      (let ((second-edges
              (map (lambda (p)
                     (edge (car p)
                       (jump-target-state-id (jump-target-kind (cdr p))
                                              (jump-target-id (cdr p)))))
                   pairs)))
        (apply provided-state (jump-prefix-state-id leader)
          'payload (list (cons 'children (list (narrowed-jump-legend-block pairs)))
                         (cons 'display
                               (list (cons 'panels
                                           (list (list (cons 'label "Jump")
                                                       (cons 'span 'wide)
                                                       (cons 'rows (list (cons 'block 'herdr-jump-legend))))))))
                         (cons 'on-enter (lambda () (paint-jump-chips-narrowed! leader)))
                         (cons 'on-leave clear-jump-chips!))
          ;; OWNER-ID (this prefix state's own id — the provider calling
          ;; convention, provider-state-id-k9) is unused: every state this
          ;; re-mint returns is Terminal, so none of them needs a parent id.
          'provider (lambda (owner-id)
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
    ;; labels instead of digit labels. Wired as presentation-gated
    ;; 'on-enter/'on-leave (not 'provider — chip paint/clear is
    ;; presentation, and rides the pair that shares the overlay's own
    ;; timing, CONTEXT.md "Action slots"; defer-chips-to-overlay-k33) on
    ;; both the herdr entry node itself (the 'herdr screen) and every
    ;; narrowing prefix state (jump-prefix-state above): chips appear WITH
    ;; the overlay, so a press fast enough to never raise it paints
    ;; nothing — and clearing pairs structurally, since run-on-leave is
    ;; guarded by the same overlay-open? that let run-on-enter fire
    ;; (fsm.sld). A narrowing descent lands with the overlay already open,
    ;; so its repaint is synchronous — only the FIRST paint waits out
    ;; `modal-overlay-delay`. Only the PANES axis is painted here; the three
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
    ;; config's (screen 'herdr …) call, mirroring
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
    ;;
    ;; OWNER-ID is the id of the state this provider is lowered onto (the
    ;; provider calling convention, provider-state-id-k9). herdr ignores it
    ;; and keeps asserting `herdr-jump-scope` — see that definition for why.
    (define (herdr-jump-provider owner-id)
      (let* ((tab-id (focused-tab-id))
             (pane-ids (jump-pane-target-ids (herdr-query "pane.list" '()) tab-id))
             (axes (parse-ui-layout (herdr-query "ui.layout" '())))
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
    ;; chips. The config wires it into its (screen 'herdr …) as an
    ;; ordinary panel child — the legend belongs to the entry node itself,
    ;; not to any drill beneath it.
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

    ;; ─── herdr entry-point activation (ADR-0013) ────────────────────
    ;;
    ;; Leader activation lands directly at the herdr entry node when the
    ;; focused pane's detection chain reaches herdr — the Terminal context
    ;; map's chain walk (resolve-activation), which also seeds the return
    ;; stack so backspace steps outward to the host screen. Nothing is
    ;; authored: `wiring` below contributes the map entry, and the config's
    ;; own (screen 'herdr …) is what it resolves to.

    ;; ─── Tab & workspace ops ────────────────────────────────────────
    ;;
    ;; `create --focus` makes and switches to the new tab/workspace;
    ;; close/rename need the focused id, read from `pane current` (one
    ;; query yields pane_id + tab_id + workspace_id).
    ;;
    ;; Reorder is the `m` Move group in the `T` / `S` drills below; its
    ;; index model is the Reorder section further down. The long-standing
    ;; "blocked on upstream herdr#770" exclusion is RETIRED —
    ;; herdr 0.7.5 ships `tab.move` / `workspace.move`
    ;; (herdr-tab-space-reorder-k36).

    (define (new-tab)       (herdr-cmd "tab.create" '(("focus" . #t))))
    (define (new-workspace) (herdr-cmd "workspace.create" '(("focus" . #t))))

    (define (close-focused-tab)
      (let ((id (focused-tab-id)))
        (when id (herdr-cmd "tab.close" (list (cons "tab_id" id))))))
    (define (close-focused-workspace)
      (let ((id (focused-workspace-id)))
        (when id (herdr-cmd "workspace.close" (list (cons "workspace_id" id))))))

    ;; herdr requires the rename label positionally (`tab rename <id>
    ;; <label>`), and prompt-on-missing-arg is unshipped herdr-repo work
    ;; with no ETA (ADR-0014, reworked at herdr-rename-prompt-ownership-k9),
    ;; so these two ops collect the label through a Modaliser-owned
    ;; chooser-prompt instead of firing bare and hitting herdr's own
    ;; usage-error exit. Look up ID's current label via the `<kind>.list` query
    ;; (the same query the live-list blocks already read) so the prompt
    ;; opens pre-filled; a failed/empty lookup degrades to "" rather than
    ;; blocking the rename.
    (define (herdr-label-for-id list-method list-key id-key id)
      (let* ((j (herdr-query list-method '()))
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

    ;; Enter submits the edited label as a plain JSON string value — no
    ;; escaping of our own, `json-write` owns it. Escape cancels the prompt
    ;; and never calls this continuation, so no herdr call fires.
    ;;
    ;; These two are plain synchronous commands. herdr's `tab.rename` /
    ;; `workspace.rename` handlers set the label in memory, emit their event
    ;; and answer immediately (measured sub-millisecond), so there is nothing
    ;; to wait for and nothing to fire-and-forget. The interactive part is
    ;; Modaliser's own chooser-prompt above, which is already CPS — ADR-0014
    ;; is satisfied by the prompt's shape, not by how the command travels.
    (define (rename-focused-tab!)
      (let ((id (focused-tab-id)))
        (when id
          (open-chooser-prompt "Rename tab…"
            (herdr-label-for-id "tab.list" "tabs" "tab_id" id)
            (lambda (label)
              (herdr-cmd "tab.rename"
                         (list (cons "tab_id" id) (cons "label" label))))))))
    (define (rename-focused-workspace!)
      (let ((id (focused-workspace-id)))
        (when id
          (open-chooser-prompt "Rename Space…"
            (herdr-label-for-id "workspace.list" "workspaces" "workspace_id" id)
            (lambda (label)
              (herdr-cmd "workspace.rename"
                         (list (cons "workspace_id" id)
                               (cons "label" label))))))))

    ;; ─── Reorder: Move Tab / Move Space (herdr-tab-space-reorder-k36) ──
    ;;
    ;; herdr 0.7.5 exposes `tab.move {tab_id, insert_index}` and
    ;; `workspace.move {workspace_id, insert_index}` (both params required),
    ;; retiring the long-recorded "blocked on upstream herdr#770" exclusion.
    ;; Neither method takes a destination scope: a tab reorders among its own
    ;; workspace's tabs, a space among all spaces.
    ;;
    ;; Three facts about the wire contract, read out of herdr 0.7.5's source
    ;; (`app/api/tabs.rs`, `app/api/workspaces.rs`, `workspace.rs::move_tab`,
    ;; `app/actions.rs::move_workspace`) rather than exercised against the
    ;; developer's live session (feedback_no_live_env_mutation_in_tests):
    ;;
    ;;  1. `insert_index` is a GAP index into the PRE-removal list, valid
    ;;     0…len inclusive (`> len` answers a `tab_move_failed` /
    ;;     `workspace_move_failed` error envelope, which by ADR-0020 is an
    ;;     answer, not a #f). The server removes then inserts, so the resulting
    ;;     position is `source < insert ? insert - 1 : insert`. That
    ;;     asymmetry is the whole reason the arithmetic below is its own
    ;;     tested function: moving one step LATER is `pos + 2`, one step
    ;;     EARLIER is `pos - 1`.
    ;;  2. Display order is the `<kind>.list` ARRAY order. A tab's `number`
    ;;     is NOT its display order — it is a stable public identity that
    ;;     rides along unchanged through a reorder (herdr's own test
    ;;     `tab_info_number_uses_stable_public_tab_number` pins this), which
    ;;     is also why `tab_id` survives a move and can be sent as the
    ;;     target. Modaliser's docs said "read-only `number` (display
    ;;     order)" for four leaves; they were wrong, and are corrected.
    ;;  3. Exactly ONE row in a whole `tab.list` payload carries
    ;;     `focused: true` — the active workspace's active tab (`focused:
    ;;     state.active == Some(ws_idx) && ws.active_tab == tab_idx`) — and
    ;;     likewise one across `workspace.list`. So a single list query
    ;;     yields target id, its position, and its scope's length together;
    ;;     no `pane.current` call is needed.
    ;;
    ;; Two decisions the wiring rests on:
    ;;
    ;; **The op reads its own index, fresh, per press** — it does NOT reuse
    ;; the drill's live-list snapshot the way digit-jump and `[`/`]` do. The
    ;; line is: reuse the snapshot when the user is CHOOSING among rows they
    ;; can see (a stale row is at worst the wrong pick), read fresh when
    ;; MUTATING (every other mutating op here already does — close reads
    ;; `pane.current`, rename reads `<kind>.list`). Reuse would also lose
    ;; presses outright: the Move keys re-arm, so a fast `l l l` that beats
    ;; the panel's re-render would recompute one insert_index three times and
    ;; the tab would advance once, not three times.
    ;;
    ;; **Either end is a no-op, not a wrap.** The `[`/`]` ring cycling wraps
    ;; (prev-next-nav-k4), but that moves FOCUS; this moves CONTENT, and its
    ;; nearest neighbour is `m` Move Pane, whose `pane.swap` no-ops at the
    ;; edge of the layout. Wrapping would also make a held key cycle a tab
    ;; around the bar forever with no resting place, where clamping parks it
    ;; at the end — the gesture users actually reach for. The edge is
    ;; expressed by returning #f from the pure arithmetic, so no request goes
    ;; out at all rather than one herdr will discard.

    ;; (reorder-insert-index position count step) → insert-index | #f
    ;;
    ;; The relative→absolute conversion, pure and total. POSITION is the
    ;; target's 0-based display index, COUNT its scope's length, STEP the
    ;; signed number of places to travel (-1 earlier / +1 later). Returns the
    ;; `insert_index` herdr wants, or #f when the move would leave the list —
    ;; the edge no-op above — which also covers a scope too short to reorder
    ;; (COUNT ≤ 1) and a POSITION outside [0, COUNT) (a malformed payload,
    ;; mirroring cycle-target-id's #f rather than erroring on a leader press).
    (define (reorder-insert-index position count step)
      (and (integer? position) (integer? count) (integer? step)
           (>= position 0) (< position count)
           (let ((final (+ position step)))
             (and (>= final 0) (< final count)
                  ;; Fact 1: the gap index. Travelling LATER, the target's own
                  ;; removal shifts everything after it down one, so the gap
                  ;; that lands it on FINAL is one further right.
                  (if (> final position) (+ final 1) final)))))

    ;; Per-kind reorder spec: (list-method array-key id-key scope-key
    ;; move-method). SCOPE-KEY is the field a reorder is confined within, or
    ;; #f for a globally-ordered kind — tabs reorder inside their workspace,
    ;; spaces reorder across the whole session. Both methods happen to name
    ;; the target under the SAME key the list rows use, so ID-KEY serves
    ;; twice (reading the row, writing the param).
    (define (reorder-spec kind)
      (cond
        ((eq? kind 'tabs)
         (list "tab.list" "tabs" "tab_id" "workspace_id" "tab.move"))
        ((eq? kind 'workspaces)
         (list "workspace.list" "workspaces" "workspace_id" #f "workspace.move"))
        (else (error "herdr reorder: unknown kind" kind))))

    ;; The focused row's place within its OWN scope: an ordered `<kind>.list`
    ;; array + the id and scope fields → (id position count), or #f when no
    ;; row is focused or it carries no usable id. Two passes over the array
    ;; because the scope is only known once the focused row is found (fact 3
    ;; guarantees there is at most one); rows outside that scope are then
    ;; skipped, so POSITION and COUNT describe the tab bar the user is
    ;; looking at rather than every tab in the session.
    (define (focused-scope-position arr id-key scope-key)
      (let ((fk (let loop ((k 0))
                  (cond
                    ((>= k (vector-length arr)) #f)
                    ((eq? (json-ref (vector-ref arr k) "focused") #t) k)
                    (else (loop (+ k 1)))))))
        (and fk
             (let ((id    (json-ref (vector-ref arr fk) id-key))
                   (scope (and scope-key
                               (json-ref (vector-ref arr fk) scope-key))))
               (and (string? id)
                    (let loop ((k 0) (i 0) (pos #f))
                      (if (>= k (vector-length arr))
                          (and pos (list id pos i))
                          (if (or (not scope-key)
                                  (equal? (json-ref (vector-ref arr k) scope-key)
                                          scope))
                              (loop (+ k 1) (+ i 1) (if (= k fk) i pos))
                              (loop (+ k 1) i pos)))))))))

    ;; (reorder-command kind parsed step) → (method . params) | #f
    ;;
    ;; The whole reorder decision as one pure function of a parsed
    ;; `<kind>.list` envelope: locate the focused row, convert STEP to an
    ;; absolute insert_index, and shape the call. #f for every "nothing to
    ;; do" — unreachable herdr (#f PARSED), malformed payload, nothing
    ;; focused, or a move off either end. Fixture-testable with no live
    ;; herdr, the same (target → call | #f) shape worktree-switch-command
    ;; has; the op below is the thin shell.
    (define (reorder-command kind parsed step)
      (let* ((spec      (reorder-spec kind))
             (array-key (list-ref spec 1))
             (id-key    (list-ref spec 2))
             (scope-key (list-ref spec 3))
             (method    (list-ref spec 4))
             (arr       (and parsed
                             (json-ref (json-ref parsed "result") array-key))))
        (and (vector? arr)
             (let ((found (focused-scope-position arr id-key scope-key)))
               (and found
                    (let ((insert (reorder-insert-index (list-ref found 1)
                                                        (list-ref found 2)
                                                        step)))
                      (and insert
                           (cons method
                                 (list (cons id-key (car found))
                                       (cons "insert_index" insert))))))))))

    ;; The op the Move keys fire: one list query, one pure decision, and at
    ;; most one command. A plain synchronous command like the renames —
    ;; herdr's move handlers reorder in memory, emit their event and answer
    ;; at once — so it rides `herdr-cmd`, not the send seam.
    (define (reorder-focused! kind step)
      (let ((call (reorder-command kind
                                   (herdr-query (car (reorder-spec kind)) '())
                                   step)))
        (when call (herdr-cmd (car call) (cdr call)))))

    ;; The four keys' ops, named spatially to match the labels they carry:
    ;; herdr draws tabs in a horizontal bar (h/l) and spaces in a vertical
    ;; sidebar (j/k), so the direction key means the direction the target
    ;; visibly travels. Earlier in the list is left/up, later is right/down.
    (define (move-tab-left)    (reorder-focused! 'tabs -1))
    (define (move-tab-right)   (reorder-focused! 'tabs  1))
    (define (move-space-up)    (reorder-focused! 'workspaces -1))
    (define (move-space-down)  (reorder-focused! 'workspaces  1))

    ;; ─── Worktree ops (the `W` Worktrees drill, W1–W4) ──────────────
    ;;
    ;; All three verbs are source-repo pinned via an explicit `workspace_id`
    ;; (the focused one, read from `pane.current`) rather than herdr's
    ;; implicit focused-workspace resolution — deterministic, and matches the
    ;; sibling tab/workspace ops. herdr's `worktree` socket methods:
    ;;   worktree.list   {workspace_id?, cwd?}
    ;;   worktree.create {workspace_id?, branch?, base?, path?, label?, focus?}
    ;;   worktree.open   {workspace_id?, branch?, path?, label?, focus?}
    ;;   worktree.remove {workspace_id, force?}

    ;; Smart-switch target parser (W4). k14 encodes each worktree row's switch
    ;; target as a tagged string it computes purely over the `worktree.list`
    ;; payload (git refs cannot contain ':', so the tag split is unambiguous):
    ;;   "ws:<id>"     open worktree     → `workspace.focus` (clean verb)
    ;;   "br:<branch>" dormant worktree  → `worktree.open` with that branch
    ;;                                      (opens a fresh workspace)
    ;; Returns a (method . params) call pair, or #f for a malformed / empty
    ;; target (a detached-dormant worktree carries no target → never dispatched).
    ;; Pure (target + source ws-id → call | #f) so it is fixture-testable with
    ;; no live herdr; the workspace pin is folded in only when SOURCE-WS-ID is a
    ;; real string (degrades to herdr's implicit resolution otherwise).
    ;;
    ;; The branch name used to be sq-escaped and single-quoted for the shell.
    ;; It is now just a JSON string value: json-write owns escaping, in one
    ;; place, for every param of every method.
    (define (worktree-switch-command target source-ws-id)
      (and (string? target)
           (>= (string-length target) 3)
           (let ((tag  (substring target 0 3))
                 (rest (substring target 3 (string-length target))))
             (and (not (string=? rest ""))
                  (cond
                    ((string=? tag "ws:")
                     (cons "workspace.focus" (list (cons "workspace_id" rest))))
                    ((string=? tag "br:")
                     (cons "worktree.open"
                           (append
                             (if (and (string? source-ws-id)
                                      (not (string=? source-ws-id "")))
                                 (list (cons "workspace_id" source-ws-id))
                                 '())
                             (list (cons "branch" rest)
                                   (cons "focus" #t)))))
                    (else #f))))))

    ;; The digit focus-fn behind the worktrees list: parse k14's tagged target
    ;; against the live focused workspace, then fire — a thin shell over the
    ;; pure parser (mirrors focus-pane-by-id / focus-tab-by-id for the other
    ;; kinds).
    (define (switch-worktree target)
      (let ((call (worktree-switch-command target (focused-workspace-id))))
        (when call (herdr-cmd (car call) (cdr call)))))

    ;; New (`n`, W1). Guard on the focused workspace id — a #f means herdr is
    ;; unreachable, so no-op — then send `worktree.create` with no `branch`.
    ;;
    ;; Omitting `branch` does NOT hand the naming to a herdr prompt: herdr's
    ;; socket API never prompts (its own branch-name dialog belongs to its TUI
    ;; key handler, which fills `branch` in before calling this same method).
    ;; The server generates a branch slug instead. `focus` still switches to
    ;; the new workspace once herdr finishes creating it.
    ;;
    ;; Sent, not called: herdr answers only after `git worktree add` returns.
    (define (new-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-send "worktree.create"
                          (list (cons "workspace_id" wsid) (cons "focus" #t))))))

    ;; Remove (`d`, W2). Acts on the FOCUSED worktree — always a valid,
    ;; unambiguous target (the focused workspace's worktree), mirroring
    ;; close-pane/tab/workspace. NO `force`: a dirty worktree or the main
    ;; checkout makes herdr/git refuse, no data loss. No Modaliser confirm
    ;; dialog — the remove-confirm UX is herdr-side; the safety that survives
    ;; here is the missing `force`. #f ws-id → no-op.
    ;;
    ;; Sent, not called, for the same reason as create above.
    (define (remove-focused-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-send "worktree.remove"
                          (list (cons "workspace_id" wsid))))))

    ;; ─── Stop Server ────────────────────────────────────────────────
    ;;
    ;; "Quit" unqualified is ambiguous between ending the herdr CLIENT and
    ;; the herdr SERVER (CONTEXT.md "Detach (herdr)" / "Stop (herdr
    ;; server)"), which is why the two are separate ops with separate
    ;; names rather than one — a config that surfaces them should name
    ;; both explicitly rather than offer a single bare "Quit" binding. The
    ;; client half, detach-op, is a prefix keystroke and therefore lives
    ;; with the other two keystroke ops, not here.

    ;; Stop Server. Ends the herdr SERVER: every pane and agent
    ;; terminates. Unlike worktree remove above (herdr-side confirm UX, no
    ;; Modaliser dialog), herdr stops the server immediately with no confirm
    ;; of its own — so this is the one herdr op that raises a Modaliser
    ;; dialog-confirm, and the CPS here is that dialog's, per ADR-0014.
    ;;
    ;; Sent, not called: herdr marks itself for quit and composes an `Ok`,
    ;; but whether that reply outruns the process exit is a race with nothing
    ;; to win — the answer is never read, so we do not ask for it.
    (define (stop-server!)
      (dialog-confirm
        "Stop the herdr server? Every pane and agent will terminate."
        (lambda (continue?)
          (when continue?
            (herdr-cmd-send "server.stop" '())))
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
    ;; (modal-handle-key's group? branch, fsm.sld); a fast
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
    ;; does — no second definition to drift out of sync.
    ;;
    ;; `pane.focus {pane_id}` is the universal by-id pane focus, so panes
    ;; and agents share focus-pane-by-id: every focus target this backend
    ;; ever holds is a pane_id — the agents axis reads `sidebar.agents[]
    ;; .pane_id` out of `ui.layout`, and next-blocked reads `agents[]
    ;; .pane_id` out of `agent.list`. `agent.focus {target}` addresses an
    ;; AGENT, which is a different (and narrower) thing: it resolves only
    ;; panes currently hosting an agent, which is exactly the regression
    ;; ADR-0020 fixes. Nothing in this file has an agent target, so nothing
    ;; in this file calls it.
    (define (focus-pane-by-id id)      (herdr-cmd "pane.focus" (list (cons "pane_id" id))))
    (define (focus-tab-by-id id)       (herdr-cmd "tab.focus" (list (cons "tab_id" id))))
    (define (focus-workspace-by-id id) (herdr-cmd "workspace.focus" (list (cons "workspace_id" id))))

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
      (let ((target (next-blocked-pane-id (herdr-query "agent.list" '())
                                          (focused-pane-id))))
        (if target
            ;; A pane_id (blocked-pane-ids reads `agents[].pane_id`), so the
            ;; universal by-id focus applies here too — not `agent.focus`.
            (focus-pane-by-id target)
            (herdr-cmd "notification.show"
                       '(("title" . "No blocked agents"))))))

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

    ;; A ring press's action: ensure a fresh snapshot for THIS kind —
    ;; the same stale-kind guard list-digit-range uses above
    ;; (herdr-fast-key-drops-k8: a fast leader→drill→step press can beat
    ;; the on-render snapshot) — then step the ring and fire FOCUS-FN on
    ;; the result. An empty ring is a silent no-op; either way the drill's
    ;; overlay refresh (triggered by the config's 'next 'self edge) re-runs
    ;; the live list's on-render-fn, so the NEXT press reads a snapshot
    ;; reflecting whatever focus this press just set.
    (define (cycle-fire! kind focus-fn scope-id-fn step)
      (let* ((targets (if (eq? kind (herdr-list-current-kind))
                          (herdr-list-current-targets)
                          (herdr-list-refresh! kind (and scope-id-fn (scope-id-fn)))))
             (target (cycle-target-id targets (herdr-list-focused-index) step)))
        (when target (focus-fn target))))

    ;; The two ring-step ops, one per direction, each over the SAME
    ;; (kind focus-fn scope-id-fn) triple the matching live-list block is
    ;; built from — so a cycling key and its list always agree on scope.
    ;; One keystroke already tours the ring, so there is no sub-mode to
    ;; enter: bind these on a cyclic edge ('next 'self) and presses chain,
    ;; the walk feel (press-press-press tours the ring with the list
    ;; updating) falling out of the overlay refresh described on
    ;; cycle-fire! above. WHICH keys, WHICH labels, and which drills get a
    ;; pair at all are the config's decisions (ADR-0021) — this library
    ;; ships only the step.
    (define (cycle-prev-op kind focus-fn scope-id-fn)
      (lambda () (cycle-fire! kind focus-fn scope-id-fn -1)))
    (define (cycle-next-op kind focus-fn scope-id-fn)
      (lambda () (cycle-fire! kind focus-fn scope-id-fn 1)))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — herdr has no provisioning step (no
    ;; config-file edits, no keybinding install); its socket works out of the
    ;; box, earning herdr the full 14/14 surface like tmux and zellij.
    (define (configured?) #t)

    ;; tool-name is #f — herdr has LEFT ADR-0017 Layer 2 entirely
    ;; (list-block-query-cutover-k32). Layer 2 exists to disambiguate a
    ;; shell-out's empty stdout, which collapses three different worlds
    ;; (binary missing / server down / genuinely nothing to list) into one
    ;; empty string, and recovers the difference by re-probing `command -v`.
    ;; The socket separates those worlds itself: a reachable herdr with
    ;; nothing to list answers a truthy `{"result":{"panes":[]}}`, while
    ;; unreachable / timeout / structured-error all answer #f. So a #f IS the
    ;; reachability verdict, consumed directly by the one reader that shows
    ;; it (the live-list blocks' unresponsive row) — no health table, no
    ;; probe, and no binary lookup on the path ADR-0020 set out to
    ;; de-subprocess. Layer 2 stays load-bearing for the CLI-native backends
    ;; (tmux, zellij, kitty, wezterm), which still have the ambiguity.
    (define backend
      (make-terminal-backend
        'herdr "herdr" 'mux "herdr" #f
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        'herdr-pane-digit
        toggle-pane-zoom
        configured?))

    ;; ─── The prefix-needing ops ─────────────────────────────────────
    ;;
    ;; Every op that needs herdr's client keybinding prefix is built here,
    ;; as a (prefix → thunk) constructor. The prefix is an ARGUMENT, never
    ;; a hidden default, so there is exactly one place it can be wrong:
    ;; the config's own binding (herdr-detach-honours-prefix-k37 fixed the
    ;; last case where it was not — Detach used to hardcode `ctrl+b`, and
    ;; failed silently, the stray keystrokes reaching the pane's shell
    ;; rather than a herdr that is not listening on them).
    ;;
    ;; THE DEFAULT-PREFIX ASSUMPTION, stated once for all three. herdr
    ;; exposes no way to query its resolved prefix, so herdr-default-prefix
    ;; is an assumption, not a reading; a config that rebound herdr's
    ;; prefix passes its own (mods key) list to these three ops instead.
    ;; The same unqueryable-default applies one level down, to the SECOND
    ;; keystroke of each pair (`[`, `e`, `q`): those bindings are
    ;; rebindable in herdr's own config too, and herdr will not tell us
    ;; what they resolved to. There is deliberately no knob for those —
    ;; a user who rebound copy_mode / edit_scrollback / detach ITSELF
    ;; writes their own one-line thunk in place of the op, which is
    ;; exactly what op grain makes cheap.
    (define herdr-default-prefix '((ctrl) "b"))

    ;; The prefix-then-key emission, in one place. Each send-keystroke is
    ;; self-contained — the modifiers are bracketed on the prefix key only —
    ;; so the trailing key carries no stray modifier. PREFIX is a (mods key)
    ;; list; mods may be empty, which send-keystroke accepts.
    (define (send-prefixed-keystroke prefix key)
      (send-keystroke (car prefix) (cadr prefix))
      (send-keystroke key))

    ;; herdr's THREE client-side keybindings, as (prefix → thunk) ops.
    ;; None has a socket or CLI verb — all three are bindings of the herdr
    ;; CLIENT, and `pane send-keys` targets the shell PTY rather than
    ;; herdr's input layer — so each emits the prefix followed by its own
    ;; second key as a keystroke pair to the FRONTMOST app, where the herdr
    ;; client is listening. Keystrokes to the frontmost app are
    ;; host-generic, which is what lets these live HERE rather than in any
    ;; host's library (the herdr screen only shows when herdr's client has
    ;; the focused pane). ADR-0020's socket cutover does not reach these:
    ;; keystroke emission was always the right mechanism here, never a
    ;; shell-out.
    ;;
    ;;   copy-mode-op   — copy_mode, default `prefix [`. herdr's per-pane
    ;;                    selection/yank mode, acting on the LIVE pane.
    ;;   scrollback-op  — edit_scrollback, default `prefix e`. Opens the
    ;;                    focused pane's scrollback BUFFER in an editor.
    ;;   detach-op      — detach-client, default `prefix q`. Ends the herdr
    ;;                    CLIENT, leaving the server and every pane running
    ;;                    (CONTEXT.md "Detach (herdr)"); contrast
    ;;                    stop-server! above, which ends the server.
    ;;
    ;; The first two are distinct operations, not spellings of one
    ;; (CONTEXT.md "Copy mode (herdr)" / "Scrollback (herdr)"), which is
    ;; exactly why they are the near-synonym pair most at risk of
    ;; collapsing back into each other under a later edit. A host
    ;; terminal's own copy mode is WRONG for both: the host sees herdr as a
    ;; SINGLE session and paints selection across the entire herdr canvas,
    ;; ignoring herdr's per-pane layout, while herdr's own bindings are
    ;; layout-aware.
    ;;
    ;; PLANE-RULE NOTE for whoever binds these (docs/specs/herdr-jump-
    ;; navigation.md). The stock composition puts copy mode on `c`, and
    ;; that lowercase key is the plane rule's ONE deliberate exception —
    ;; which means `c` MUST stay out of the jump label pools above,
    ;; because a static edge shadows a provider-supplied one, so a `c` jump
    ;; label would be silently unreachable rather than an error. That
    ;; constraint lives in the pools, and moving the BINDING into user
    ;; configuration does not move it: rebind copy mode off `c` freely, but
    ;; do not expect `c` to become a jump label. A capital (the stock
    ;; scrollback key `C`) cannot collide with a label at all — the pools
    ;; are lowercase-only.
    (define (copy-mode-op prefix)
      (lambda () (send-prefixed-keystroke prefix "[")))    ; copy_mode

    (define (scrollback-op prefix)
      (lambda () (send-prefixed-keystroke prefix "e")))    ; edit_scrollback

    (define (detach-op prefix)
      (lambda () (send-prefixed-keystroke prefix "q")))    ; detach-client

    ;; ─── The wiring fragment (library-fragments-k11, ADR-0021) ──────

    ;; (wiring) → herdr's Fragment: the Terminal-context-map entry
    ;; ("herdr" → the 'herdr tree, driven by the 'herdr backend), the
    ;; backend record, and the digit-jump mode tree the record's
    ;; focus-pane-by-digit slot names at fire time. Integration only —
    ;; ADR-0013's "inner-tool wiring lives with the inner tool", narrowed
    ;; by ADR-0021 to facilities: no host is named anywhere, and no key or
    ;; label is authored anywhere.
    ;;
    ;; What is NOT here, and lives in the user's config.scm instead, is the
    ;; (screen 'herdr …) itself — the drills, the keys, the labels, the
    ;; panels — together with the three things it must wire onto that
    ;; screen for the jump space to work (see default-config.scm for the
    ;; stock composition to copy):
    ;;
    ;;   'provider herdr-jump-provider — the jump space: on every
    ;;     come-to-rest it gathers visible panes/spaces/agents/tabs,
    ;;     assigns lowercase jump labels, and lowers them to live edges.
    ;;   'on-enter paint-jump-chips! / 'on-leave clear-jump-chips! —
    ;;     full-size jump-letter chips painted over the on-screen panes
    ;;     when the overlay ACTUALLY displays this screen, cleared on leave
    ;;     (presentation-gated Action slots — chips appear with the
    ;;     overlay, so a press fast enough to never raise it paints
    ;;     nothing; defer-chips-to-overlay-k33). The same pair rides every
    ;;     narrowing prefix state inside the provider's own lowering, which
    ;;     IS machinery and stays here.
    ;;   (panel "Jump" (jump-legend-block)) — reads the SAME per-visit
    ;;     snapshot the chips paint from, so legend and chips always agree.
    ;;
    ;; The tree scope 'herdr is machinery, not preference: the context
    ;; entry below references it by key, so a screen authored under another
    ;; scope fails reference-closure validation at load. Likewise
    ;; 'herdr-panes-focus, which the config's Focus rows cross into via
    ;; 'next and which the config registers itself.
    ;;
    ;; Activation, the outward backspace, and the host's gated "." step-in
    ;; all derive from the context map machinery (resolve-activation /
    ;; the seeded stack / the lowering-composed step-in provider) — the
    ;; app-tree's detection gate, entry row, and up-edge wiring have no
    ;; equivalent here because nothing needs authoring.
    ;;
    ;; Each call builds fresh tree objects: compose ONE call's value (two
    ;; calls' same-scope contributions are a merge conflict, not a
    ;; diamond).
    (define (wiring)
      (list
        (config:context "herdr" 'tree 'herdr 'backend 'herdr)
        (config:backend 'herdr backend)
        (config:tree 'herdr-pane-digit (pane-digit-tree))))))
