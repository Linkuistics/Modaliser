import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser muxes herdr)` — the herdr backend behind the
/// (modaliser terminal) façade.
///
/// These run without a herdr session attached. The shell-out helpers
/// return #f / empty in that case, which is the contract the façade
/// expects, so registration and wiring are verifiable end-to-end without
/// a live server. Hand-verification of the 14 ops against a live iTerm +
/// herdr client is the leaf's separate "Done when" item (the JSON-parse
/// path itself is covered by ModaliserJsonLibraryTests).
@Suite("(modaliser muxes herdr) library")
struct ModaliserMuxesHerdrLibraryTests {

    /// A herdr screen authored the way a configuration authors one
    /// (ADR-0021) — the library ships ops, blocks and the jump provider;
    /// every key and label below belongs to this fixture, exactly as
    /// default-config.scm's belong to the seed.
    ///
    /// It is a FIXTURE, not a replica of the stock composition: only the
    /// paths the dispatch tests below actually press are here. The real
    /// seed is loaded and lowered for real by
    /// `ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors`, which is
    /// the one seam that pins it (ADR-0021's Consequences: library
    /// tree-shape tests are deleted rather than relocated, because
    /// asserting `Q d` = Detach asserts preference).
    ///
    /// Assumes `(modaliser dsl)`, `(modaliser fsm)`, `(modaliser muxes
    /// herdr)` and `(prefix (modaliser configuration) config:)` are
    /// imported, and leaves the graph installed and `cfg` bound.
    private static let herdrScreenFixture = """
      (define (fixture-cycle kind focus-fn scope-id-fn)
        (splice
          (key "[" "Prev" (cycle-prev-op kind focus-fn scope-id-fn) 'next 'self)
          (key "]" "Next" (cycle-next-op kind focus-fn scope-id-fn) 'next 'self)))
      (define cfg (config:configuration
        (screen 'herdr
          'display-name "herdr"
          'provider herdr-jump-provider
          'on-enter paint-jump-chips!
          'on-leave clear-jump-chips!
          (open "P" "Panes"
            (panel "Focus"
              (key "h" "Left"  focus-pane-left  'next 'herdr-panes-focus)
              (key "j" "Down"  focus-pane-down  'next 'herdr-panes-focus)
              (key "k" "Up"    focus-pane-up    'next 'herdr-panes-focus)
              (key "l" "Right" focus-pane-right 'next 'herdr-panes-focus))
            (group "m" "Move"
              'exit-on-unknown #t
              (key "h" "Left"  move-pane-left  'next 'self)
              (key "j" "Down"  move-pane-down  'next 'self)
              (key "k" "Up"    move-pane-up    'next 'self)
              (key "l" "Right" move-pane-right 'next 'self))
            (fixture-cycle 'panes focus-pane-by-id focused-tab-id)
            (panel "Panes" (pane-list-block 'chips? #t)))
          (open "S" "Spaces"
            (fixture-cycle 'workspaces focus-workspace-by-id #f)
            (panel "Spaces" (workspace-list-block)))
          (open "A" "Agents"
            (fixture-cycle 'agents focus-pane-by-id #f)
            (panel "Agents" (agent-list-block)))
          (key "c" "Copy Mode" (copy-mode-op herdr-default-prefix))
          (panel "Jump" (jump-legend-block)))
        (config:tree 'herdr-panes-focus
          (tree-root 'herdr-panes-focus
            'exit-on-unknown #t
            'display-name "Focus"
            (key "h" "Left"  focus-pane-left  'next 'self)
            (key "j" "Down"  focus-pane-down  'next 'self)
            (key "k" "Up"    focus-pane-up    'next 'self)
            (key "l" "Right" focus-pane-right 'next 'self)
            (fixture-cycle 'panes focus-pane-by-id focused-tab-id)))))
      (fsm-install-graph! (lower-configuration cfg))
      """

    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        // The public composition surface (ADR-0021): the wiring fragment
        // and the backend record, plus the op / block / provider names a
        // config's own (screen 'herdr …) binds. All must bind without
        // error — a name that vanished here is a broken config, loudly.
        for name in [
            "wiring", "backend", "herdr-default-prefix",
            "focus-pane-left", "split-pane-up", "move-pane-right",
            "toggle-pane-zoom", "close-pane",
            "new-tab", "close-focused-tab", "rename-focused-tab!",
            "new-workspace", "close-focused-workspace", "rename-focused-workspace!",
            "move-tab-left", "move-space-down",
            "new-worktree!", "remove-focused-worktree!",
            "jump-to-next-blocked", "stop-server!",
            "focus-pane-by-id", "focus-tab-by-id", "focus-workspace-by-id",
            "focused-tab-id", "focused-workspace-id",
            "cycle-prev-op", "cycle-next-op",
            "copy-mode-op", "scrollback-op", "detach-op",
            "pane-list-block", "tab-list-block", "workspace-list-block",
            "agent-list-block", "worktree-list-block",
            "herdr-jump-provider", "paint-jump-chips!", "clear-jump-chips!",
            "jump-legend-block"
        ] {
            _ = try engine.evaluate(name)
        }
    }

    /// The backend record installs into the façade's registry, keyed
    /// by 'herdr + match-key "herdr". With a stubbed host reporting
    /// "herdr" as its foreground command, the façade walks the path and
    /// the leaf is this backend — the detection premise validated live
    /// against the herdr-in-iTerm client (an iTerm pane running herdr
    /// reports tty foreground command "herdr").
    @Test func installedBackendResolvesInTheChainWalk() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl)
                  (modaliser muxes herdr) (modaliser terminal))
        """)

        // A stub host that claims herdr is in the focused pane. The path
        // walk descends from host into the herdr backend; without a live
        // herdr session the backend's detect-fg returns #f, so it sits at
        // the leaf naturally.
        try engine.evaluate("""
          (define stub-host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle" #f
              (lambda () "herdr")      ; foreground command → descend into herdr
              (lambda () "host-1")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (terminal-install-backends! (list backend stub-host))
        """)

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "test.bundle")))
            (length (focused-terminal-path)))
        """)
        #expect(pathLen == .fixnum(2))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "test.bundle")))
            (in-chain? 'herdr))
        """)
        #expect(inChain == .true)
    }

    /// The wiring fragment carries the digit-pick mode tree, so the
    /// backend record's focus-pane-by-digit symbol ('herdr-pane-digit)
    /// names a real tree for the façade's resolver to hand a
    /// procedure-valued 'next.
    @Test func wiringCarriesDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr))
        """)
        try engine.evaluate("(define cfg (config:configuration (wiring)))")
        #expect(try engine.evaluate("(config:configuration-tree-ref cfg \"herdr-pane-digit\")") != .false)
    }

    /// The exported `backend` record is shape-correct: matches as a mux
    /// against the "herdr" foreground command and reports configured? =
    /// #t (no provisioning). This is the contract the façade reads when
    /// resolving the active backend — herdr gets the full 14-op surface.
    @Test func backendRecordIsShapeCorrect() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("""
          (define h
            (make-terminal-backend
              'sh "H" 'host "t.b" #f
              (lambda () "herdr") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (terminal-install-backends! (list backend h))
        """)
        // All four capability predicates should report support: herdr
        // gives the full 14-op surface (12 focus/split/move + digit-jump
        // + zoom-toggle).
        for predicate in [
            "(supports-splits?)",
            "(supports-move-pane?)",
            "(supports-digit-jump?)",
            "(supports-zoom?)"
        ] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id (lambda () "t.b")))
                \(predicate))
            """) == .true, "expected \(predicate) ⇒ #t")
        }
    }

    /// The backend record's match-key is "herdr" and kind is 'mux — the
    /// façade indexes mux backends by foreground-command match-key, so a
    /// wrong key would silently never resolve. Guards the detection
    /// contract validated live (#1).
    @Test func backendMatchesHerdrForegroundKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser terminal))")
        // A host reporting some *other* fg command must NOT resolve herdr.
        try engine.evaluate("""
          (define other-host
            (make-terminal-backend
              'other "Other" 'host "other.bundle" #f
              (lambda () "bash") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (terminal-install-backends! (list backend other-host))
        """)
        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "other.bundle")))
            (in-chain? 'herdr))
        """)
        #expect(inChain == .false)
    }

    // MARK: - herdr-in-iTerm entry-point wiring (leaf 3, ADR-0013)

    /// `iterm-list-session-ids` (apps/iterm's pane-UUID source) stays
    /// exported but is asserted only, not called (it would auto-launch
    /// iTerm via AppleScript).
    @Test func itermSessionIdSourceStaysExported() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr)
                  (only (modaliser apps iterm) iterm-list-session-ids))
        """)
        #expect(try engine.evaluate("(procedure? iterm-list-session-ids)") == .true)
    }

    // MARK: - Dispatch through an authored herdr screen
    //
    // These press keys, so they need a tree. They author their own
    // (ADR-0021) — see `herdrScreenFixture` — and what they assert is the
    // MACHINERY the presses reach: cyclic vs cross edges, the live-list
    // blocks' stale-kind guard, the jump provider's lowering. Which key
    // carries which op is the fixture's own choice, asserted nowhere.

    /// ADR-0015 live smoke: a Move group whose hjkl each carry 'next 'self
    /// (a cyclic edge), so repeat presses re-arm in place — no exit, no
    /// modal-stack growth — and an unrelated key still exits per
    /// 'exit-on-unknown.
    @Test func movePaneWalkReArmsInPlaceAndExitsOnUnknownKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("(modal-activate! \"herdr\" '() F18)")
        try engine.evaluate("(modal-handle-key \"P\")")
        try engine.evaluate("(modal-handle-key \"m\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"P\" \"m\"))") == .true)

        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"P\" \"m\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-handle-key \"q\")") // unbound in Move
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    /// ADR-0015 live smoke: a Focus panel whose hjkl carry
    /// 'next 'herdr-panes-focus (a cross edge) — the first press pushes the
    /// caller (the herdr screen, inside the Panes drill) and switches into
    /// the Walk; subsequent hjkl inside it cycle via 'next 'self with no
    /// further push; backspace pops back to the caller.
    ///
    /// 'herdr-panes-focus is the one scope symbol here that is NOT the
    /// fixture's choice: it is machinery-named, and a config that renames
    /// it fails reference-closure validation at load.
    @Test func focusPanelCrossesIntoWalkThenCyclesInPlace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("(modal-activate! \"herdr\" '() F18)")
        try engine.evaluate("(modal-handle-key \"P\")") // Panes drill
        try engine.evaluate("(modal-handle-key \"h\")") // Focus panel
        #expect(try engine.evaluate(
            "(eq? modal-root-node (config:configuration-tree-ref cfg \"herdr-panes-focus\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-handle-key \"j\")")
        try engine.evaluate("(modal-handle-key \"k\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate(
            "(eq? modal-root-node (config:configuration-tree-ref cfg \"herdr\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    /// herdr-fast-key-drops-k8: reproduces the reported "leader, S, <digit>
    /// typed fast doesn't work" bug and proves the fix. (Spaces was `w` at
    /// the time this bug was fixed; top-level-nav-k6 moved it to capital
    /// `S` — the guard itself is unaffected by which key reaches the drill.)
    ///
    /// current-targets / current-kind is ONE cell shared by every herdr-list
    /// kind (the single-render invariant, blocks/herdr-list.sld). A group
    /// descent only renders synchronously when the overlay is already open
    /// (modal-handle-key's group? branch, state-machine.sld) — never true in
    /// this hermetic harness, which installs no overlay backend, exactly
    /// mirroring a real press faster than modal-overlay-delay. So pressing
    /// "S" then a digit here reaches the digit key-range without Spaces
    /// ever having snapshotted.
    ///
    /// Simulates a Panes render earlier in the session (current-kind =
    /// 'panes, label "1" → a pane id), then presses "S" "1" with no
    /// Spaces render in between: the digit must not accept the stale
    /// Panes entry just because it happens to sit under the same label — it
    /// must detect the kind mismatch, force a fresh `workspace list`
    /// snapshot, and resolve "1" against THAT data. Before the kind guard,
    /// the bare (assoc "1" current-targets) hit the stale Panes id directly,
    /// herdr-list-refresh! for 'workspaces was never called, and the wrong
    /// (often since-invalid) id fired — the fast-typing failure the human
    /// reported.
    @Test func digitPressBeforeRenderIgnoresStaleOtherKindEntry() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr)
                  (modaliser blocks herdr-list) (modaliser json))
        """)
        try engine.evaluate(Self.herdrScreenFixture)

        // Prior render this session: Panes, label "1" → a stale pane id.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "pane.list")
                    (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"focused\":true,\"pane_id\":\"STALE-PANE\",\"tab_id\":\"w1:t1\"}]}}"))
                   (else #f)))))
            (herdr-list-refresh! 'panes #f))
        """#)
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'panes)") == .true)
        #expect(try engine.evaluate("(cdr (assoc \"1\" (herdr-list-current-targets)))")
                == .string("STALE-PANE"))

        // Fast leader→S→1: the overlay never opens in this harness, so "S"'s
        // descent does not render Spaces before "1" fires.
        //
        // The digit ends in a real focus verb, so the WRITE seam is stubbed
        // alongside the read seam. Stubbing one and not its sibling is the
        // gap that used to put `workspace.focus REAL-WORKSPACE` on the
        // developer's live socket (test-live-herdr-contact-k35); capturing
        // here also lets the test assert the verb, which is the altitude
        // ADR-0020 says matters.
        try engine.evaluate("(define FIRED '())")
        try engine.evaluate("(modal-activate! \"herdr\" '() F18)")
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "workspace.list")
                    (json-parse "{\"result\":{\"workspaces\":[{\"focused\":true,\"label\":\"work\",\"workspace_id\":\"REAL-WORKSPACE\"}]}}"))
                   (else #f))))
             (current-herdr-command-runner
               (lambda (method params)
                 (set! FIRED (cons (cons method params) FIRED))
                 #f)))
            (modal-handle-key "S")
            (modal-handle-key "1"))
        """#)

        // The digit forced a real Spaces snapshot instead of trusting
        // the stale Panes entry under the same label.
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'workspaces)") == .true)
        #expect(try engine.evaluate("(cdr (assoc \"1\" (herdr-list-current-targets)))")
                == .string("REAL-WORKSPACE"))
        // …and focused it, by workspace id, over the socket.
        #expect(try engine.evaluate("(car (car FIRED))") == .string("workspace.focus"))
        #expect(try engine.evaluate("(cdr (assoc \"workspace_id\" (cdr (car FIRED))))")
                == .string("REAL-WORKSPACE"))
    }

    /// The pure JSON→(targets . rows) extractor over a real `herdr pane list`
    /// fixture. Panes carry no `label`, so the row title falls back to the
    /// agent name (else the pane id); the digit targets map label→pane_id in
    /// list order; the `focused` flag rides through. No live herdr needed —
    /// this is the "JSON-fed list rendering" contract.
    @Test func herdrListExtractParsesPanes() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"cwd\":\"/w/one\",\"focused\":true,\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\"},{\"cwd\":\"/w/two\",\"focused\":false,\"pane_id\":\"w9:p2\",\"tab_id\":\"w9:t2\"}]}}"))
          (define R (herdr-list-extract 'panes (list "1" "2" "3") J #f))
          (define TARGETS (car R))
          (define ROWS (cdr R))
        """#)
        // Two entries → two targets, label→pane_id in order.
        #expect(try engine.evaluate("(length TARGETS)") == .fixnum(2))
        #expect(try engine.evaluate("(cdr (assoc \"1\" TARGETS))") == .string("w9:p1"))
        #expect(try engine.evaluate("(cdr (assoc \"2\" TARGETS))") == .string("w9:p2"))
        // Row 1: agent name as title, cwd as detail, focused #t.
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS)))") == .string("claude"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (car ROWS)))") == .string("/w/one"))
        #expect(try engine.evaluate("(cdr (assoc 'focused (car ROWS)))") == .true)
        // Row 2: no agent → title falls back to the pane id; not focused.
        #expect(try engine.evaluate("(cdr (assoc 'title (cadr ROWS)))") == .string("w9:p2"))
        #expect(try engine.evaluate("(cdr (assoc 'focused (cadr ROWS)))") == .false)
    }

    /// Tabs and workspaces carry a `label`, so the row title is the label and
    /// the target id is the tab_id / workspace_id. Guards the per-kind spec
    /// (array key + id key + title key) the shared block dispatches on.
    @Test func herdrListExtractParsesTabsAndWorkspaces() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        // Tabs.
        try engine.evaluate(#"""
          (define JT (json-parse "{\"result\":{\"tabs\":[{\"focused\":true,\"label\":\"1 claude\",\"tab_id\":\"w9:t1\"},{\"focused\":false,\"label\":\"2 hunk\",\"tab_id\":\"w9:t2\"}]}}"))
          (define RT (herdr-list-extract 'tabs (list "1" "2") JT #f))
        """#)
        #expect(try engine.evaluate("(cdr (assoc \"2\" (car RT)))") == .string("w9:t2"))
        #expect(try engine.evaluate("(cdr (assoc 'title (car (cdr RT))))") == .string("1 claude"))
        // Workspaces.
        try engine.evaluate(#"""
          (define JW (json-parse "{\"result\":{\"workspaces\":[{\"focused\":true,\"label\":\"TestAnyware\",\"workspace_id\":\"w9\"}]}}"))
          (define RW (herdr-list-extract 'workspaces (list "1") JW #f))
        """#)
        #expect(try engine.evaluate("(cdr (assoc \"1\" (car RW)))") == .string("w9"))
        #expect(try engine.evaluate("(cdr (assoc 'title (car (cdr RW))))") == .string("TestAnyware"))
    }

    /// A malformed / empty list (herdr not running → parsed #f) extracts to
    /// empty targets and rows rather than raising — the contract the block's
    /// on-render-fn relies on so a render never breaks a leader press.
    @Test func herdrListExtractDegradesToEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list))")
        try engine.evaluate("(define R (herdr-list-extract 'panes (list \"1\" \"2\") #f #f))")
        #expect(try engine.evaluate("(null? (car R))") == .true)
        #expect(try engine.evaluate("(null? (cdr R))") == .true)
    }

    /// pane-list-tab-local-k3: `herdr pane list` is GLOBAL (confirmed against a
    /// live server — panes from every workspace/tab, no `result.source` to
    /// compare against, same as tabs), so the panes kind is scoped by the
    /// caller-supplied focused-tab-id — a pane whose tab_id doesn't match is
    /// dropped in phase 1, before labels are assigned. A four-pane, two-tab
    /// fixture: only wC:t1's two panes become rows/digit targets, relabeled
    /// "1"/"2" (not the fixture's original JSON positions 1 and 3).
    @Test func herdrListExtractScopesPanesToFocusedTab() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"cwd\":\"/w/one\",\"focused\":true,\"pane_id\":\"wC:p1\",\"tab_id\":\"wC:t1\"},{\"cwd\":\"/w/two\",\"focused\":false,\"pane_id\":\"wD:p1\",\"tab_id\":\"wD:t1\"},{\"cwd\":\"/w/three\",\"focused\":false,\"pane_id\":\"wC:p2\",\"tab_id\":\"wC:t1\"},{\"cwd\":\"/w/four\",\"focused\":false,\"pane_id\":\"wD:p2\",\"tab_id\":\"wD:t1\"}]}}"))
          (define R (herdr-list-extract 'panes (list "1" "2" "3" "4") J "wC:t1"))
          (define TARGETS (car R))
          (define ROWS (cdr R))
        """#)
        // Only wC:t1's two panes survive — wD:t1's are dropped, not just unlabeled.
        #expect(try engine.evaluate("(length TARGETS)") == .fixnum(2))
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(2))
        #expect(try engine.evaluate("(cdr (assoc \"1\" TARGETS))") == .string("wC:p1"))
        #expect(try engine.evaluate("(cdr (assoc \"2\" TARGETS))") == .string("wC:p2"))
        #expect(try engine.evaluate("(if (assoc \"3\" TARGETS) #t #f)") == .false)
        #expect(try engine.evaluate("(cdr (assoc 'detail (car ROWS)))") == .string("/w/one"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (cadr ROWS)))") == .string("/w/three"))
    }

    /// A #f focused-tab-id (herdr unreachable, `pane current` failed) degrades
    /// to unfiltered — every tab's panes still render — rather than an empty
    /// list. Non-panes kinds ignore the parameter outright: a tab_id-bearing
    /// fixture (agents also carry tab_id) is unaffected by a scope value.
    @Test func herdrListExtractPanesUnfilteredWithoutFocusedTab() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"focused\":true,\"pane_id\":\"wC:p1\",\"tab_id\":\"wC:t1\"},{\"focused\":false,\"pane_id\":\"wD:p1\",\"tab_id\":\"wD:t1\"}]}}"))
          (define R (herdr-list-extract 'panes (list "1" "2") J #f))
        """#)
        #expect(try engine.evaluate("(length (car R))") == .fixnum(2))
    }

    /// herdr-tabs-workspace-local-k3: `herdr tab list` is GLOBAL (confirmed
    /// against a live server — it carries every workspace's tabs, unlike
    /// `worktree list` it has no `result.source` to compare against), so the
    /// tabs kind is scoped by the caller-supplied focused-workspace-id — a tab
    /// whose workspace_id doesn't match is dropped in phase 1, before labels
    /// are assigned. A four-tab, two-workspace fixture: only wC's two tabs
    /// become rows/digit targets, relabeled "1"/"2" (not the fixture's
    /// original JSON positions 1 and 3).
    @Test func herdrListExtractScopesTabsToFocusedWorkspace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"tabs\":[{\"focused\":true,\"label\":\"1 Claude\",\"tab_id\":\"wC:t1\",\"workspace_id\":\"wC\"},{\"focused\":false,\"label\":\"2 Yazi\",\"tab_id\":\"wC:t2\",\"workspace_id\":\"wC\"},{\"focused\":false,\"label\":\"1 Claude\",\"tab_id\":\"wD:t1\",\"workspace_id\":\"wD\"},{\"focused\":false,\"label\":\"2 Yazi\",\"tab_id\":\"wD:t2\",\"workspace_id\":\"wD\"}]}}"))
          (define R (herdr-list-extract 'tabs (list "1" "2" "3" "4") J "wC"))
          (define TARGETS (car R))
          (define ROWS (cdr R))
        """#)
        // Only wC's two tabs survive — wD's are dropped, not just unlabeled.
        #expect(try engine.evaluate("(length TARGETS)") == .fixnum(2))
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(2))
        #expect(try engine.evaluate("(cdr (assoc \"1\" TARGETS))") == .string("wC:t1"))
        #expect(try engine.evaluate("(cdr (assoc \"2\" TARGETS))") == .string("wC:t2"))
        #expect(try engine.evaluate("(if (assoc \"3\" TARGETS) #t #f)") == .false)
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS)))") == .string("1 Claude"))
        #expect(try engine.evaluate("(cdr (assoc 'title (cadr ROWS)))") == .string("2 Yazi"))
    }

    /// A #f focused-workspace-id (herdr unreachable, `pane current` failed)
    /// degrades to unfiltered — every workspace's tabs still render — rather
    /// than an empty list. Non-tabs kinds ignore the parameter outright: a
    /// workspace_id-bearing fixture (agents also carry workspace_id) is
    /// unaffected by a scope value.
    @Test func herdrListExtractTabsUnfilteredWithoutFocusedWorkspace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"tabs\":[{\"focused\":true,\"label\":\"1 Claude\",\"tab_id\":\"wC:t1\",\"workspace_id\":\"wC\"},{\"focused\":false,\"label\":\"1 Claude\",\"tab_id\":\"wD:t1\",\"workspace_id\":\"wD\"}]}}"))
          (define R (herdr-list-extract 'tabs (list "1" "2") J #f))
        """#)
        #expect(try engine.evaluate("(length (car R))") == .fixnum(2))
    }

    // MARK: - Agents list (leaf agents-list-block-k12)

    /// The `'agents` kind: rows come from `agent list`, each carries a `status`
    /// from `agent_status`, and the list is reordered status-priority (blocked →
    /// working → idle → unknown) BEFORE labels are assigned — so digit "1"
    /// focuses the first blocked agent (D7). Within a status band the input
    /// (pane_id) order is preserved (stable). Titles fall back to the agent name
    /// (agent rows carry no `label`); the detail annotates the agent's location
    /// (tab_id, D2). Fixture-fed — no live herdr.
    @Test func herdrListExtractAgentsOrdersBlockedFirst() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        // Input order deliberately NOT status-sorted: idle, blocked, working,
        // blocked, unknown. Two blocked agents (p2 before p4) exercise the
        // stable within-band order.
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"agents\":[{\"agent\":\"idle-a\",\"agent_status\":\"idle\",\"focused\":false,\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"},{\"agent\":\"blk-a\",\"agent_status\":\"blocked\",\"focused\":false,\"pane_id\":\"w9:p2\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"},{\"agent\":\"wrk-a\",\"agent_status\":\"working\",\"focused\":true,\"pane_id\":\"w9:p3\",\"tab_id\":\"w9:t2\",\"workspace_id\":\"w9\"},{\"agent\":\"blk-b\",\"agent_status\":\"blocked\",\"focused\":false,\"pane_id\":\"w9:p4\",\"tab_id\":\"w9:t2\",\"workspace_id\":\"w9\"},{\"agent\":\"unk-a\",\"agent_status\":\"unknown\",\"focused\":false,\"pane_id\":\"w9:p5\",\"tab_id\":\"w9:t3\",\"workspace_id\":\"w9\"}]}}"))
          (define R (herdr-list-extract 'agents (list "1" "2" "3" "4" "5") J #f))
          (define TARGETS (car R))
          (define ROWS (cdr R))
          (define (row i) (list-ref ROWS i))
          (define (rf i k) (cdr (assoc k (row i))))
        """#)
        // Five agents → five targets, reordered blocked-first before labeling.
        #expect(try engine.evaluate("(length TARGETS)") == .fixnum(5))
        // Digit 1 / 2 → the two blocked agents, stable pane_id order (p2, p4).
        #expect(try engine.evaluate("(cdr (assoc \"1\" TARGETS))") == .string("w9:p2"))
        #expect(try engine.evaluate("(cdr (assoc \"2\" TARGETS))") == .string("w9:p4"))
        // Digit 3 → working; 4 → idle; 5 → unknown.
        #expect(try engine.evaluate("(cdr (assoc \"3\" TARGETS))") == .string("w9:p3"))
        #expect(try engine.evaluate("(cdr (assoc \"4\" TARGETS))") == .string("w9:p1"))
        #expect(try engine.evaluate("(cdr (assoc \"5\" TARGETS))") == .string("w9:p5"))
        // Rows follow the same reordered sequence: row 0 = first blocked agent,
        // carrying its status, the agent name as title, and tab_id as detail.
        #expect(try engine.evaluate("(rf 0 'title)") == .string("blk-a"))
        #expect(try engine.evaluate("(rf 0 'status)") == .string("blocked"))
        #expect(try engine.evaluate("(rf 0 'detail)") == .string("w9:t1"))
        #expect(try engine.evaluate("(rf 1 'status)") == .string("blocked"))
        #expect(try engine.evaluate("(rf 2 'status)") == .string("working"))
        #expect(try engine.evaluate("(rf 2 'focused)") == .true)
        #expect(try engine.evaluate("(rf 3 'status)") == .string("idle"))
        #expect(try engine.evaluate("(rf 4 'status)") == .string("unknown"))
    }

    /// Scope guard: the `status` field is populated ONLY for the `'agents`
    /// kind. A panes row must NOT carry `status` even when its JSON has an
    /// `agent_status`, so the panes/tabs/workspaces lists render exactly as
    /// before (no badge). Guards the "populate only for 'agents" contract.
    @Test func herdrListExtractNonAgentsCarryNoStatus() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"agent_status\":\"idle\",\"cwd\":\"/w/one\",\"focused\":true,\"pane_id\":\"w9:p1\"}]}}"))
          (define ROWS (cdr (herdr-list-extract 'panes (list "1") J #f)))
        """#)
        #expect(try engine.evaluate("(if (assoc 'status (car ROWS)) #t #f)") == .false)
    }

    // MARK: - Worktrees list (leaf worktrees-list-block-k14)

    /// The `'worktrees` kind: rows come from `worktree list`, but — unlike the
    /// four field-reading kinds — both the digit target and the current row are
    /// COMPUTED over the parsed payload. The target is a tagged string:
    /// "ws:<open_workspace_id>" for an OPEN worktree (jump to the live
    /// workspace), "br:<branch>" for a DORMANT one (open a fresh workspace on
    /// the branch). The CURRENT row (cursor seed) is the worktree whose
    /// open_workspace_id equals result.source.source_workspace_id — both ride
    /// in the one payload. Title = branch, falling back to label then path
    /// basename for a DETACHED worktree with no branch; detail = the path with
    /// a folded-in ● open / ○ dormant marker (no status badge). Fixture-fed —
    /// no live herdr.
    @Test func herdrListExtractParsesWorktrees() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        // Four worktrees: main (open, current — its ws == source w9), feature-x
        // (open elsewhere, ws w12 ≠ w9), ocr-accuracy (dormant, has a branch),
        // and a detached worktree (no branch → label fallback, dormant → no
        // digit target).
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"source\":{\"source_workspace_id\":\"w9\"},\"worktrees\":[{\"branch\":\"main\",\"label\":\"main\",\"path\":\"/repo\",\"open_workspace_id\":\"w9\",\"is_detached\":false},{\"branch\":\"feature-x\",\"label\":\"feature-x\",\"path\":\"/repo/.grove-worktrees/feature-x\",\"open_workspace_id\":\"w12\",\"is_detached\":false},{\"branch\":\"ocr-accuracy\",\"label\":\"ocr\",\"path\":\"/repo/.grove-worktrees/ocr-accuracy\",\"is_detached\":false},{\"label\":\"detached-wt\",\"path\":\"/repo/.grove-worktrees/detached-dir\",\"is_detached\":true}]}}"))
          (define R (herdr-list-extract 'worktrees (list "1" "2" "3" "4") J #f))
          (define TARGETS (car R))
          (define ROWS (cdr R))
          (define (row i) (list-ref ROWS i))
          (define (rf i k) (cdr (assoc k (row i))))
        """#)
        // Three targets: the detached-dormant worktree (row 3) is unswitchable
        // (no live workspace, no branch) so it carries NO digit target — but it
        // still consumed label "4" and renders as a row.
        #expect(try engine.evaluate("(length TARGETS)") == .fixnum(3))
        // Tagged targets: open → "ws:<id>"; dormant → "br:<branch>".
        #expect(try engine.evaluate("(cdr (assoc \"1\" TARGETS))") == .string("ws:w9"))
        #expect(try engine.evaluate("(cdr (assoc \"2\" TARGETS))") == .string("ws:w12"))
        #expect(try engine.evaluate("(cdr (assoc \"3\" TARGETS))") == .string("br:ocr-accuracy"))
        #expect(try engine.evaluate("(if (assoc \"4\" TARGETS) #t #f)") == .false)
        // Current row: only main (open_workspace_id w9 == source w9). The other
        // open worktree (w12) is NOT current, and dormant rows never are.
        #expect(try engine.evaluate("(rf 0 'focused)") == .true)
        #expect(try engine.evaluate("(rf 1 'focused)") == .false)
        #expect(try engine.evaluate("(rf 2 'focused)") == .false)
        #expect(try engine.evaluate("(rf 3 'focused)") == .false)
        // Titles: branch normally; the detached row falls back to its label.
        #expect(try engine.evaluate("(rf 0 'title)") == .string("main"))
        #expect(try engine.evaluate("(rf 2 'title)") == .string("ocr-accuracy"))
        #expect(try engine.evaluate("(rf 3 'title)") == .string("detached-wt"))
        // Detail: path with the folded-in open/dormant marker.
        #expect(try engine.evaluate("(rf 0 'detail)") == .string("● /repo"))
        #expect(try engine.evaluate("(rf 2 'detail)")
                == .string("○ /repo/.grove-worktrees/ocr-accuracy"))
        // The unswitchable detached row still displays label "4", no dispatch.
        #expect(try engine.evaluate("(rf 3 'label)") == .string("4"))
        // Worktree rows carry NO status (no badge) — like panes/tabs/workspaces.
        #expect(try engine.evaluate("(if (assoc 'status (row 0)) #t #f)") == .false)
    }

    /// The detached worktree's title falls all the way back to the path
    /// basename when it has neither a branch NOR a label — the last-resort leg
    /// of branch → label → path-basename.
    @Test func herdrListExtractWorktreeTitleFallsBackToPathBasename() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"source\":{\"source_workspace_id\":\"w9\"},\"worktrees\":[{\"path\":\"/repo/.grove-worktrees/loose-dir\",\"is_detached\":true}]}}"))
          (define ROWS (cdr (herdr-list-extract 'worktrees (list "1") J #f)))
        """#)
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS)))") == .string("loose-dir"))
        // Dormant + no branch → no target, and ○ dormant marker in the detail.
        #expect(try engine.evaluate("(cdr (assoc 'detail (car ROWS)))")
                == .string("○ /repo/.grove-worktrees/loose-dir"))
    }

    /// The current-row guard: with NO source (source_workspace_id absent) NO
    /// row may be marked current — not even a dormant one. Guards the json-ref
    /// #f-vs-#f trap (a bare (equal? open_workspace_id source_workspace_id)
    /// would fire #f == #f and wrongly mark every dormant worktree current).
    @Test func herdrListExtractWorktreesNoSourceMeansNoCurrent() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"worktrees\":[{\"branch\":\"a\",\"path\":\"/x\",\"open_workspace_id\":\"w1\"},{\"branch\":\"b\",\"path\":\"/y\"}]}}"))
          (define ROWS (cdr (herdr-list-extract 'worktrees (list "1" "2") J #f)))
        """#)
        // Open row: target still built, but not current (no source to match).
        #expect(try engine.evaluate("(cdr (assoc 'focused (car ROWS)))") == .false)
        // Dormant row: the #f-vs-#f trap would mark this current — it must not.
        #expect(try engine.evaluate("(cdr (assoc 'focused (cadr ROWS)))") == .false)
    }

    // MARK: - Pane chips (leaf herdr-pane-chips-k10)

    /// The pure chip-rect synthesis over a real `herdr pane layout` fixture.
    /// Given the label→pane_id targets (from `pane list`), the parsed layout
    /// (per-pane cell rects + the sidebar-offset area), and the focused iTerm
    /// AXScrollArea pixel frame, `herdr-chip-entries` places each chip at the
    /// pane's top-left in host pixels. CANVAS-RELATIVE is the crux, verified
    /// live (2026-07-14, herdr 0.7.3, herdr-chip-offset-k5): `area` (100×50
    /// here) is only the pane sub-region — herdr's left sidebar occupies the
    /// other area.x=26 columns of the FULL 126-wide canvas the AXScrollArea
    /// maps to (confirmed against a live session's own column count via
    /// iTerm's scripting bridge: area.x + area.width == total columns). Pane
    /// rects are already absolute cells in that full canvas, so the leftmost
    /// pane's chip x must land INSET from host.x by the sidebar's pixel
    /// width (host.x + 26·cell_w), not at host.x itself — and cell_w divides
    /// by the total canvas width (126), not by area.width (100) alone. A
    /// target whose pane_id is absent from the current-tab layout (a
    /// cross-tab pane) yields NO chip: chips are a subset of rows.
    @Test func herdrChipEntriesSynthesisesCanvasRelativeRects() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        // area 100×50 cells offset by the x=26 sidebar (full canvas = 126×50);
        // host 1260×500 px at (200,100) → cell_w = cell_h = 10. Two
        // side-by-side panes filling the area (26..76, 76..126); a third
        // target (w9:p9) is off-tab and not in this layout.
        try engine.evaluate(#"""
          (define LAYOUT (json-parse "{\"result\":{\"layout\":{\"area\":{\"x\":26,\"y\":0,\"width\":100,\"height\":50},\"focused_pane_id\":\"w9:p1\",\"zoomed\":false,\"panes\":[{\"pane_id\":\"w9:p1\",\"focused\":true,\"rect\":{\"x\":26,\"y\":0,\"width\":50,\"height\":50}},{\"pane_id\":\"w9:p2\",\"focused\":false,\"rect\":{\"x\":76,\"y\":0,\"width\":50,\"height\":50}}]}}}"))
          (define TARGETS (list (cons "1" "w9:p1") (cons "2" "w9:p2") (cons "3" "w9:p9")))
          (define HOST (list (cons 'x 200) (cons 'y 100) (cons 'w 1260) (cons 'h 500)))
          (define ENTRIES (herdr-chip-entries TARGETS LAYOUT HOST))
          (define (chip lab key) (cdr (assoc key (cdr (assoc lab ENTRIES)))))
        """#)
        // Only the two on-screen panes get chips (p9 is off-tab → dropped).
        #expect(try engine.evaluate("(length ENTRIES)") == .fixnum(2))
        // Pane 1: leftmost PANE, but not the canvas's left edge — the sidebar
        // (26 cols · 10 px) sits before it. chip.x = 200 + 260 = 460.
        #expect(try engine.evaluate("(chip \"1\" 'x)") == .fixnum(460))
        #expect(try engine.evaluate("(chip \"1\" 'y)") == .fixnum(100))
        #expect(try engine.evaluate("(chip \"1\" 'w)") == .fixnum(500))
        #expect(try engine.evaluate("(chip \"1\" 'h)") == .fixnum(500))
        // Pane 2: 76 cells · 10 px = 760 → x = 200 + 760 = 960; pane 2's
        // right edge (76+50=126 cells · 10 px = 1260) lands exactly on the
        // host's right edge (host.x + host.w = 200 + 1260 = 1460).
        #expect(try engine.evaluate("(chip \"2\" 'x)") == .fixnum(960))
        #expect(try engine.evaluate("(chip \"2\" 'y)") == .fixnum(100))
        #expect(try engine.evaluate("(chip \"2\" 'w)") == .fixnum(500))
    }

    /// Defensive: no host frame (iTerm AX query returned nothing) or a
    /// malformed/#f layout (herdr not running) yields no chips rather than
    /// raising — the on-render paint path must never break a leader press.
    @Test func herdrChipEntriesDegradesToEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define LAYOUT (json-parse "{\"result\":{\"layout\":{\"area\":{\"x\":26,\"y\":0,\"width\":100,\"height\":50},\"panes\":[{\"pane_id\":\"w9:p1\",\"rect\":{\"x\":26,\"y\":0,\"width\":100,\"height\":50}}]}}}"))
          (define HOST (list (cons 'x 0) (cons 'y 0) (cons 'w 800) (cons 'h 600)))
          (define TS (list (cons "1" "w9:p1")))
        """#)
        // No host → empty.
        #expect(try engine.evaluate("(null? (herdr-chip-entries TS LAYOUT #f))") == .true)
        // No layout → empty.
        #expect(try engine.evaluate("(null? (herdr-chip-entries TS #f HOST))") == .true)
    }

    // MARK: - Grid calibration (leaf herdr-canvas-pixel-calibration-k42)

    /// The AXScrollArea frame is NOT the character grid. Measured live
    /// (2026-07-19, via AXBoundsForRange on iTerm's text area): raw scroll
    /// frame (1706,64,3410,2096) vs a glyph grid whose top-left cell sits at
    /// (1711,66) — iTerm's default 5pt side / 2pt top margins — with exactly
    /// 8×18pt cells, so a 425×116-cell canvas really spans 3400×2088 and the
    /// frame's remaining 4pt is sub-cell slack (a tiled window's height isn't
    /// cell-quantized). Scaling cell rects by the RAW frame stretched the
    /// mapping ~0.3%, drifting chips proportionally to the coordinate (the
    /// k42 symptom). herdr-grid-frame swaps the raw frame for the true grid:
    /// origin = the measured top-left cell, extent = canvas × cell size.
    @Test func herdrGridFrameCalibratesHostToMeasuredCells() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list))")
        try engine.evaluate(#"""
          (define CELL (list (cons 'x 1711.0) (cons 'y 66.0)
                             (cons 'w 8.0) (cons 'h 18.0)))
          (define RAW  (list (cons 'x 1706) (cons 'y 64)
                             (cons 'w 3410) (cons 'h 2096)))
          (define GRID (herdr-grid-frame CELL RAW 425 116))
          (define (g key) (cdr (assoc key GRID)))
        """#)
        #expect(try engine.evaluate("(g 'x)") == .fixnum(1711))
        #expect(try engine.evaluate("(g 'y)") == .fixnum(66))
        #expect(try engine.evaluate("(g 'w)") == .fixnum(3400))
        #expect(try engine.evaluate("(g 'h)") == .fixnum(2088))
    }

    /// End-to-end against the live-captured `ui layout` response from the
    /// same session: with the CALIBRATED grid frame, the agents mini-chip
    /// entries land exactly on the rows AXBoundsForRange measured — wC:p1
    /// (cell y=61) at pixel y = 66 + 61·18 = 1164, wF:p1 (y=63) at 1200 —
    /// where the raw scroll frame used to put them at 1166/1202 (the live
    /// drift this leaf was opened on).
    @Test func uiLayoutChipEntriesLandOnMeasuredCellPositions() throws {
        let engine = try SchemeEngine()
        try engine.evaluate(
            "(import (modaliser muxes herdr) (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define PARSED (json-parse "{\"id\":\"cli:ui:layout\",\"result\":{\"canvas\":{\"height\":116,\"width\":425},\"layout\":\"desktop\",\"obscured\":false,\"sidebar\":{\"agents\":[{\"pane_id\":\"wC:p1\",\"rect\":{\"height\":2,\"width\":25,\"x\":0,\"y\":61}},{\"pane_id\":\"wF:p1\",\"rect\":{\"height\":2,\"width\":25,\"x\":0,\"y\":63}}],\"mode\":\"expanded\",\"rect\":{\"height\":116,\"width\":26,\"x\":0,\"y\":0},\"workspaces\":[{\"focused\":true,\"rect\":{\"height\":2,\"width\":25,\"x\":0,\"y\":2},\"workspace_id\":\"wC\"},{\"focused\":false,\"rect\":{\"height\":2,\"width\":25,\"x\":0,\"y\":4},\"workspace_id\":\"wF\"}]},\"tab_bar\":{\"rect\":{\"height\":0,\"width\":0,\"x\":0,\"y\":0},\"tabs\":[],\"workspace_id\":\"wC\"},\"type\":\"ui_layout\"}}"))
          (define CELL (list (cons 'x 1711.0) (cons 'y 66.0)
                             (cons 'w 8.0) (cons 'h 18.0)))
          (define RAW  (list (cons 'x 1706) (cons 'y 64)
                             (cons 'w 3410) (cons 'h 2096)))
          (define HOST (herdr-grid-frame CELL RAW 425 116))
          (define ES (ui-layout-agent-chip-entries
                       (list (cons "h" "wC:p1") (cons "i" "wF:p1"))
                       PARSED HOST))
          (define (chip lab key) (cdr (assoc key (cdr (assoc lab ES)))))
        """#)
        #expect(try engine.evaluate("(length ES)") == .fixnum(2))
        // Row 61 → 66 + 61·18 = 1164 (AXBoundsForRange measured 1164.00).
        #expect(try engine.evaluate("(chip \"h\" 'y)") == .fixnum(1164))
        // Row 63 → 66 + 63·18 = 1200 (measured 1200.00).
        #expect(try engine.evaluate("(chip \"i\" 'y)") == .fixnum(1200))
        // Col 0 starts at the grid origin (1711, NOT the frame's 1706); the
        // 25-cell-wide entry spans exactly 25·8 = 200px, 2 rows = 36px.
        #expect(try engine.evaluate("(chip \"h\" 'x)") == .fixnum(1711))
        #expect(try engine.evaluate("(chip \"h\" 'w)") == .fixnum(200))
        #expect(try engine.evaluate("(chip \"h\" 'h)") == .fixnum(36))
    }

    /// Calibration degrades, never breaks: a missing/degenerate measured
    /// cell, or one whose derived grid can't fit inside the raw frame (a
    /// double-width first glyph would double the extent), falls back to the
    /// RAW frame unchanged; no raw frame at all stays #f (the paint path's
    /// existing no-host degradation).
    @Test func herdrGridFrameFallsBackToRawFrame() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-list))")
        try engine.evaluate(#"""
          (define RAW (list (cons 'x 1706) (cons 'y 64)
                            (cons 'w 3410) (cons 'h 2096)))
          (define (raw? v) (equal? v RAW))
        """#)
        // No measured cell → raw unchanged.
        #expect(try engine.evaluate("(raw? (herdr-grid-frame #f RAW 425 116))") == .true)
        // Degenerate cell (zero width) → raw.
        #expect(try engine.evaluate(#"""
          (raw? (herdr-grid-frame
                  (list (cons 'x 1711.0) (cons 'y 66.0)
                        (cons 'w 0.0) (cons 'h 18.0))
                  RAW 425 116))
        """#) == .true)
        // A 16pt-wide "cell" (double-width first glyph) puts the derived
        // grid outside the scroll frame → rejected, raw kept.
        #expect(try engine.evaluate(#"""
          (raw? (herdr-grid-frame
                  (list (cons 'x 1711.0) (cons 'y 66.0)
                        (cons 'w 16.0) (cons 'h 18.0))
                  RAW 425 116))
        """#) == .true)
        // No raw frame (iTerm unreachable) → #f, as today.
        #expect(try engine.evaluate(#"""
          (not (herdr-grid-frame
                 (list (cons 'x 1711.0) (cons 'y 66.0)
                       (cons 'w 8.0) (cons 'h 18.0))
                 #f 425 116))
        """#) == .true)
    }

    /// The measuring primitive itself degrades to #f for an app that isn't
    /// running (and, transitively, for any AX failure along the chain) —
    /// the paint path must never raise on a headless/AX-less run.
    @Test func axFirstVisibleCharBoundsDegradesToFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser accessibility))")
        #expect(try engine.evaluate(
            "(not (ax-first-visible-char-bounds \"com.example.not-running\"))") == .true)
    }

    // MARK: - Agents tree wiring (leaf agents-tree-wiring-k13)

    /// The pure jump-to-blocked ring helper. From a parsed `agent list`, the
    /// blocked agents (agent_status == "blocked") are ordered by pane_id and
    /// `next-blocked-pane-id` returns the first blocked pane_id sorting strictly
    /// AFTER the currently-focused pane, wrapping to the first blocked pane when
    /// focus is at/after the last (round-robin, not a Walk — D4). Fixture-fed,
    /// no live herdr. (pane_id compare is lexical for v1: fine while ids share a
    /// width; noted in the source.)
    @Test func nextBlockedPaneIdRoundRobin() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        // Two blocked agents (p2, p5) interleaved with idle/working, JSON order
        // deliberately not status-sorted. p1 idle, p2 blocked, p3 working, p5
        // blocked.
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"agents\":[{\"agent\":\"a1\",\"agent_status\":\"idle\",\"pane_id\":\"w9:p1\"},{\"agent\":\"a2\",\"agent_status\":\"blocked\",\"pane_id\":\"w9:p2\"},{\"agent\":\"a3\",\"agent_status\":\"working\",\"pane_id\":\"w9:p3\"},{\"agent\":\"a4\",\"agent_status\":\"blocked\",\"pane_id\":\"w9:p5\"}]}}"))
        """#)
        // Focus before both blocked → first blocked (p2).
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p1\")") == .string("w9:p2"))
        // Focus ON the first blocked → advance to the next (p5).
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p2\")") == .string("w9:p5"))
        // Focus ON the last blocked → wrap to the first (p2).
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p5\")") == .string("w9:p2"))
        // Focus on a NON-blocked agent mid-ring (working p3) → next blocked (p5).
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p3\")") == .string("w9:p5"))
        // Focus on an ABSENT/higher id → wrap to the first blocked (p2).
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p9\")") == .string("w9:p2"))
        // No focus id at all (pane current unreadable) → first blocked (p2).
        #expect(try engine.evaluate("(next-blocked-pane-id J #f)") == .string("w9:p2"))
    }

    /// No blocked agent anywhere → #f, which drives the op's `notification show`
    /// path (D5) rather than a focus change. A malformed / #f parse (herdr not
    /// running) is likewise #f, never raising.
    @Test func nextBlockedPaneIdNoneBlocked() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"agents\":[{\"agent\":\"a1\",\"agent_status\":\"idle\",\"pane_id\":\"w9:p1\"},{\"agent\":\"a2\",\"agent_status\":\"working\",\"pane_id\":\"w9:p2\"}]}}"))
        """#)
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p1\")") == .false)
        // #f parse (herdr down) → #f, no raise.
        #expect(try engine.evaluate("(next-blocked-pane-id #f \"w9:p1\")") == .false)
    }

    /// One blocked agent → returned regardless of where focus sits (before,
    /// on it, or after) — the single-element ring always resolves to it.
    @Test func nextBlockedPaneIdSingle() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"agents\":[{\"agent\":\"a1\",\"agent_status\":\"idle\",\"pane_id\":\"w9:p1\"},{\"agent\":\"a2\",\"agent_status\":\"blocked\",\"pane_id\":\"w9:p3\"}]}}"))
        """#)
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p1\")") == .string("w9:p3"))
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p3\")") == .string("w9:p3"))
        #expect(try engine.evaluate("(next-blocked-pane-id J \"w9:p9\")") == .string("w9:p3"))
    }

    // MARK: - The socket transport itself (ADR-0020)
    //
    // Every other test in this file stubs current-herdr-query-runner /
    // current-herdr-command-runner, which is right for exercising dispatch
    // but leaves the transport underneath them — envelope construction,
    // reply parsing, error mapping — with no coverage of its own. These
    // three run the REAL transport against a throwaway responder, so no
    // herdr need be installed, let alone running.

    /// The request format is a contract with herdr, so pin the exact bytes:
    /// one compact JSON line, `{"id","method","params"}`, params rendered
    /// from the alist the callers pass. The primitive owns the trailing
    /// newline, so the recorded line carries none.
    @Test func transportPutsAJsonRpcEnvelopeOnTheWireAndParsesTheReply() throws {
        let responder = try LineResponderSocket(
            behaviour: .canned(#"{"id":"modaliser","result":{"pane":{"pane_id":"wC:p4"}}}"#))
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json))")
        let paneId = try engine.evaluate(#"""
          (parameterize ((current-herdr-socket-path "\#(responder.path)"))
            (let ((reply (herdr-socket-request "pane.focus" '(("pane_id" . "wC:p4")))))
              (json-ref (json-ref (json-ref reply "result") "pane") "pane_id")))
        """#)

        #expect(paneId == .makeString("wC:p4"))
        #expect(responder.lastRequest
                == #"{"id":"modaliser","method":"pane.focus","params":{"pane_id":"wC:p4"}}"#)
    }

    /// A structured `{"error":…}` reply is an ANSWER, not silence — this is
    /// the exact response that used to arrive as `agent_not_found` and get
    /// discarded by `2>/dev/null`. It comes back as its envelope (and is
    /// logged), because `#f` is reserved for "herdr did not answer": a
    /// caller reporting herdr's state to the user must not read
    /// `worktree.list` → `not_git_worktree` as "herdr is not responding".
    /// Callers need no branch for it — an error envelope has no "result",
    /// and `json-ref` is total, so it degrades to the same empty a `#f`
    /// would have produced.
    @Test func transportReturnsAnErrorReplyAsItsEnvelopeNotFalse() throws {
        let responder = try LineResponderSocket(
            behaviour: .canned(#"{"id":"modaliser","error":{"code":"agent_not_found","message":"nope"}}"#))
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define REPLY
            (parameterize ((current-herdr-socket-path "\#(responder.path)"))
              (herdr-socket-request "agent.focus" '(("target" . "wC:p4")))))
        """#)
        // Answered, not silent…
        #expect(try engine.evaluate("(if REPLY #t #f)") == .true)
        #expect(try engine.evaluate("(json-ref (json-ref REPLY \"error\") \"code\")")
                == .string("agent_not_found"))
        // …and still nothing for a reader to consume, exactly as before.
        #expect(try engine.evaluate("(json-ref REPLY \"result\")") == .false)
    }

    /// An unreachable socket — herdr not running — degrades to #f without
    /// raising. A leader press must never raise (ADR-0014/0017 spirit).
    /// This is what #f now means, and the only thing it means.
    @Test func transportDegradesToFalseWhenHerdrIsUnreachable() throws {
        let absent = LineResponderSocket.temporarySocketPath()
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr))")
        #expect(try engine.evaluate(#"""
          (parameterize ((current-herdr-socket-path "\#(absent)"))
            (herdr-socket-request "pane.current" '()))
        """#) == .false)
    }

    // MARK: - The transport is inert until the host installs a path (k35)

    /// The structural guard that keeps `swift test` off the developer's own
    /// herdr session: `current-herdr-socket-path` defaults to #f, so a bare
    /// `SchemeEngine()` has nowhere to dial and every herdr call degrades to
    /// the #f each caller already handles. Only the app bootstrap (root.scm)
    /// installs the live path.
    ///
    /// Together with the default being #f, these two returns ARE the whole
    /// guarantee: `current-herdr-socket-path` is the only thing either
    /// transport dials, so an unconfigured parameter cannot reach a socket by
    /// any route. That is what makes the safety structural rather than a
    /// per-test habit — the leak this replaced came from tests with no herdr
    /// I/O intent at all (a backend-record shape check, the detection chain
    /// walk, a Move-walk re-arm), which had no reason to stub a seam.
    @Test func transportIsInertUntilTheHostInstallsASocketPath() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr))")

        #expect(try engine.evaluate("(current-herdr-socket-path)") == .false)
        #expect(try engine.evaluate("(herdr-socket-request \"pane.current\" '())") == .false)
        #expect(try engine.evaluate("(herdr-socket-send \"server.stop\" '())") == .false)
        // And through the seams the ops actually use, unstubbed — the exact
        // route by which `pane.swap` used to reach a live pane layout.
        #expect(try engine.evaluate("""
          ((current-herdr-command-runner) "pane.swap" '(("direction" . "left")))
        """) == .false)
        #expect(try engine.evaluate("""
          ((current-herdr-query-runner) "pane.list" '())
        """) == .false)
    }

    /// Installing is the host's job; resolving is still herdr's. The policy
    /// root.scm hands to the parameter stays here, unchanged from when it was
    /// a load-time expression: $HERDR_SOCKET_PATH wins when Modaliser is run
    /// from a shell inside herdr, and the $HOME fallback is what a
    /// GUI-launched Modaliser (stripped environment) actually uses.
    @Test func defaultSocketPathResolvesTheHostPolicy() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket))")
        let resolved = try engine.evaluate("(herdr-default-socket-path)")

        if let exported = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"] {
            #expect(resolved == .makeString(exported))
        } else {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            #expect(resolved == .makeString(home + "/.config/herdr/herdr.sock"))
        }
    }

    /// The distinction end-to-end, at the one place it is user-visible: a
    /// live-list drill shows the "not responding" row ONLY for silence. An
    /// `error` envelope — herdr answering with an objection, e.g.
    /// `worktree.list` → not_git_worktree outside a git work tree — renders
    /// as an ordinary empty list, which is what the CLI era did too.
    @Test func anErrorReplyRendersAnEmptyListNotTheUnresponsiveRow() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser blocks herdr-list)
                  (modaliser json))
        """)
        try engine.evaluate("(define B (make-herdr-list-block 'kind 'worktrees))")
        try engine.evaluate(#"""
          (define ROWS
            (cdr (assoc 'rows
              (parameterize
                ((current-herdr-query-runner
                   (lambda (method params)
                     (json-parse "{\"id\":\"modaliser\",\"error\":{\"code\":\"not_git_worktree\",\"message\":\"Herdr worktree actions require a workspace inside a Git work tree\"}}"))))
                ((cdr (assoc 'on-render-fn B)))))))
        """#)
        #expect(try engine.evaluate("(null? ROWS)") == .true)
        #expect(try engine.evaluate("(null? (herdr-list-current-targets))") == .true)
    }

    // MARK: - Worktrees tree wiring (leaf worktrees-tree-wiring-k15)

    /// The pure smart-switch target parser (W4). k14 hands each worktree row a
    /// tagged switch target computed over the `worktree.list` payload; this
    /// turns it back into a herdr socket call — a (method . params) pair. An
    /// OPEN worktree ("ws:<id>") maps to the clean `workspace.focus`; a DORMANT
    /// one ("br:<branch>") maps to `worktree.open` on that branch, source-pinned
    /// with `workspace_id` when the focused ws-id is known. Malformed / empty /
    /// non-string targets → #f (never dispatched). Fixture-fed — no live herdr.
    ///
    /// The branch name is no longer sq-escaped: it is a JSON string value now,
    /// and `json-write` owns escaping for every param of every method (ADR-0020).
    /// The apostrophe case below therefore asserts the branch arrives VERBATIM —
    /// that shell quoting is gone, not merely relocated.
    @Test func worktreeSwitchCommandParsesTarget() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        // Open worktree → focus its live workspace (no source pin needed).
        #expect(try engine.evaluate(#"""
          (equal? (worktree-switch-command "ws:w12" "w9")
                  '("workspace.focus" ("workspace_id" . "w12")))
        """#) == .true)
        // Dormant worktree → open a fresh workspace on the branch, source-pinned.
        #expect(try engine.evaluate(#"""
          (equal? (worktree-switch-command "br:feature-x" "w9")
                  '("worktree.open" ("workspace_id" . "w9")
                                    ("branch" . "feature-x")
                                    ("focus" . #t)))
        """#) == .true)
        // No focused ws-id → degrade to herdr's implicit resolution (no pin).
        #expect(try engine.evaluate(#"""
          (equal? (worktree-switch-command "br:feature-x" #f)
                  '("worktree.open" ("branch" . "feature-x") ("focus" . #t)))
        """#) == .true)
        // An apostrophe in the branch travels verbatim — no shell quoting left.
        #expect(try engine.evaluate(#"""
          (equal? (cdr (assoc "branch" (cdr (worktree-switch-command "br:it's" "w9"))))
                  "it's")
        """#) == .true)
        // Malformed tag, empty payload, and non-string all → #f (no dispatch).
        #expect(try engine.evaluate(#"(worktree-switch-command "xx:foo" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "ws:" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "br:" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "" "w9")"#) == .false)
        #expect(try engine.evaluate("(worktree-switch-command #f \"w9\")") == .false)
    }

    // MARK: - The send seam: ops whose reply is deliberately not awaited

    /// worktree create/remove go out through `unix-socket-send`, not
    /// `unix-socket-request`, because herdr answers them only once a
    /// `git worktree add`/`remove` subprocess finishes — waiting would block
    /// the eval thread for the transport's full timeout as a matter of
    /// routine (ADR-0014's stalled-tap hazard).
    ///
    /// What is pinned here is the pair that reaches the socket. `create`
    /// carries NO `branch`: herdr's socket API never prompts (its
    /// branch-name dialog belongs to its own TUI key handler, upstream of
    /// the API), so omitting it means "server, generate a slug" — not "ask
    /// the user". `remove` carries no `force`, which is the whole safety
    /// story for that op: git refuses a dirty worktree.
    ///
    /// Both the id-resolution query and the send are routed through
    /// parameterized seams, so no test reaches a real herdr
    /// (feedback_no_live_env_mutation_in_tests).
    @Test func worktreeOpsSendExactMethodAndParamsWithFocusedId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define captured '())
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}")))
             (current-herdr-send-runner
               (lambda (method params)
                 (set! captured (cons (cons method params) captured)))))
            (new-worktree!)
            (remove-focused-worktree!))
          (set! captured (reverse captured))
          (define (call-method n) (car (list-ref captured n)))
          (define (call-param n key)
            (let ((hit (assoc key (cdr (list-ref captured n))))) (and hit (cdr hit))))
          (define (has-param? n key) (if (assoc key (cdr (list-ref captured n))) #t #f))
        """#)
        #expect(try engine.evaluate("(call-method 0)") == .string("worktree.create"))
        #expect(try engine.evaluate(#"(call-param 0 "workspace_id")"#) == .string("w9"))
        #expect(try engine.evaluate(#"(call-param 0 "focus")"#) == .true)
        // The absence is the assertion: a `branch` here would be Modaliser
        // naming the user's branch, and a `force` below would be Modaliser
        // overriding git's refusal to delete a dirty worktree.
        #expect(try engine.evaluate(#"(has-param? 0 "branch")"#) == .false)

        #expect(try engine.evaluate("(call-method 1)") == .string("worktree.remove"))
        #expect(try engine.evaluate(#"(call-param 1 "workspace_id")"#) == .string("w9"))
        #expect(try engine.evaluate(#"(has-param? 1 "force")"#) == .false)
    }

    /// The send transport's own coverage, mirroring the request transport's
    /// above: the REAL `herdr-socket-send` against a throwaway responder,
    /// pinning the same `{"id","method","params"}` envelope. Sharing the
    /// envelope builder with `herdr-socket-request` is what makes that
    /// identity structural rather than coincidental, and this is what would
    /// catch it drifting.
    @Test func sendTransportPutsTheSameJsonRpcEnvelopeOnTheWire() throws {
        let responder = try LineResponderSocket(behaviour: .canned(#"{"id":"modaliser"}"#))
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr))")
        #expect(try engine.evaluate(#"""
          (parameterize ((current-herdr-socket-path "\#(responder.path)"))
            (herdr-socket-send "worktree.create" '(("workspace_id" . "w9") ("focus" . #t))))
        """#) == .true)

        #expect(responder.awaitRequest()
                == #"{"id":"modaliser","method":"worktree.create","params":{"workspace_id":"w9","focus":true}}"#)
    }

    /// An unreachable herdr degrades to #f here exactly as it does on the
    /// request side — never a raise, because a leader press must not raise.
    @Test func sendTransportDegradesToFalseWhenHerdrIsUnreachable() throws {
        let absent = LineResponderSocket.temporarySocketPath()
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr))")
        #expect(try engine.evaluate(#"""
          (parameterize ((current-herdr-socket-path "\#(absent)"))
            (herdr-socket-send "server.stop" '()))
        """#) == .false)
    }

    // MARK: - The rename ops (plain synchronous commands)

    /// herdr-rename-prompt-ownership-k9: the two rename ops don't fire bare —
    /// they open a Modaliser-owned chooser-prompt (via the (modaliser fsm)
    /// open-chooser-prompt deferred hook, the same shape open-chooser uses)
    /// pre-filled with the id's current label, read via `tab.list` (the same
    /// query the live-list blocks already use). Only submitting the prompt's
    /// continuation issues the command.
    ///
    /// That command is a PLAIN SYNCHRONOUS one: herdr's `tab.rename` handler
    /// sets the label in memory, emits its event and answers immediately, so
    /// there is nothing to wait for and no reason to send-and-forget. The
    /// interactive half is Modaliser's own prompt, which is already CPS —
    /// ADR-0014 is satisfied by the prompt's shape, not by how the command
    /// travels. Hence `current-herdr-command-runner` here, the same seam the
    /// other synchronous verbs use.
    ///
    /// open-chooser-prompt is a plain setter (not a parameter), so it's
    /// stubbed directly rather than parameterized — the stub captures the
    /// (prompt, initial-value, on-submit) triple without a real WebView.
    @Test func renameFocusedTabOpensPromptPrefilledAndSendsLabelOnSubmit() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser fsm) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define captured-prompt #f)
          (define captured-initial #f)
          (define captured-submit #f)
          (define captured-call #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit)
              (set! captured-prompt prompt)
              (set! captured-initial initial)
              (set! captured-submit on-submit)))
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "pane.current")
                    (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}"))
                   ((string=? method "tab.list")
                    (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w9:t1\",\"label\":\"main\"}]}}"))
                   (else #f))))
             (current-herdr-command-runner
               (lambda (method params) (set! captured-call (cons method params)))))
            (rename-focused-tab!)
            (captured-submit "feature work"))
          (define (param key)
            (let ((hit (assoc key (cdr captured-call)))) (and hit (cdr hit))))
        """#)
        #expect(try engine.evaluate("captured-prompt").asString() == "Rename tab…")
        #expect(try engine.evaluate("captured-initial").asString() == "main")
        #expect(try engine.evaluate("(car captured-call)") == .string("tab.rename"))
        #expect(try engine.evaluate(#"(param "tab_id")"#) == .string("w9:t1"))
        #expect(try engine.evaluate(#"(param "label")"#) == .string("feature work"))
    }

    /// Same shape as the tab test above, on the label that used to be the
    /// interesting one: an apostrophe. Under the shell it had to arrive
    /// POSIX-single-quote-escaped (`'it'\''s mine'`) or it broke the command;
    /// the assertion now is the inverse — the label must reach the params
    /// **verbatim**, because escaping is no longer this code's business.
    ///
    /// So this runs the REAL transport rather than stubbing the seam: the
    /// claim worth pinning is not "we pass the string along" but "what lands
    /// on the wire is valid JSON with the apostrophe intact", and only
    /// `json-write` can be caught getting that wrong.
    @Test func renameFocusedWorkspaceSendsAnApostropheLabelUnescapedAsJson() throws {
        let responder = try LineResponderSocket(behaviour: .canned(#"{"id":"modaliser","result":{}}"#))
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser fsm) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define captured-initial #f)
          (define captured-submit #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit)
              (set! captured-initial initial)
              (set! captured-submit on-submit)))
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (json-parse "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w9\",\"label\":\"work\"}],\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}")))
             (current-herdr-socket-path "\#(responder.path)"))
            (rename-focused-workspace!)
            (captured-submit "it's mine"))
        """#)
        #expect(try engine.evaluate("captured-initial").asString() == "work")

        // An apostrophe needs no escaping in JSON; a backslash before it here
        // would mean someone reintroduced shell-shaped quoting.
        #expect(responder.awaitRequest()
                == #"{"id":"modaliser","method":"workspace.rename","params":{"workspace_id":"w9","label":"it's mine"}}"#)
    }

    /// The guard: with no focused id (herdr unreachable — `pane.current`
    /// resolves to #f), all four ops no-op — neither runner, nor (for the two
    /// rename ops) open-chooser-prompt, is ever invoked. Both the command and
    /// send seams are stubbed, since the four ops now divide across them. The
    /// query runner is explicitly stubbed to #f rather than relying on the
    /// ambient environment lacking herdr, so the assertion holds regardless
    /// of whether the host machine has a live herdr session.
    @Test func fourHerdrOpsNoOpWithoutFocusedId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser fsm) (modaliser json))
        """)
        try engine.evaluate("""
          (define fired? #f)
          (define prompted? #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit) (set! prompted? #t)))
          (parameterize
            ((current-herdr-query-runner (lambda (method params) #f))
             (current-herdr-command-runner (lambda (method params) (set! fired? #t)))
             (current-herdr-send-runner (lambda (method params) (set! fired? #t))))
            (rename-focused-tab!)
            (rename-focused-workspace!)
            (new-worktree!)
            (remove-focused-worktree!))
        """)
        #expect(try engine.evaluate("fired?") == .false)
        #expect(try engine.evaluate("prompted?") == .false)
    }

    // MARK: - Reorder: Move Tab / Move Space (leaf herdr-tab-space-reorder-k36)

    /// The relative→absolute arithmetic, exhaustively. herdr's
    /// `insert_index` is a GAP index into the PRE-removal list — the server
    /// removes the target then inserts at that gap, landing it on
    /// `source < insert ? insert - 1 : insert` — so the two directions are
    /// NOT symmetric: one place later is `pos + 2`, one place earlier is
    /// `pos - 1`. That asymmetry is the reason this is its own function.
    ///
    /// Either end returns #f rather than wrapping (the `[`/`]` ring wraps,
    /// but that moves focus; this moves content, and its neighbour `m` Move
    /// Pane no-ops at the edge of the layout). #f means the op sends no
    /// request at all.
    @Test func reorderInsertIndexConvertsRelativeStepsToHerdrGapIndex() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")

        // A four-long scope, target at position 1. Later → 1+2 = 3 (the gap
        // past position 2, which becomes position 2 once the target is
        // removed); earlier → 1-1 = 0. Asymmetric by two, not by zero.
        #expect(try engine.evaluate("(reorder-insert-index 1 4 1)") == .fixnum(3))
        #expect(try engine.evaluate("(reorder-insert-index 1 4 -1)") == .fixnum(0))
        // From the second-to-last place, moving later lands on the last:
        // insert 4 == the list length, which herdr accepts (`> len` errors).
        #expect(try engine.evaluate("(reorder-insert-index 2 4 1)") == .fixnum(4))
        // Both edges are no-ops, not wraps.
        #expect(try engine.evaluate("(reorder-insert-index 0 4 -1)") == .false)
        #expect(try engine.evaluate("(reorder-insert-index 3 4 1)") == .false)
        // A scope too short to reorder, and an empty one.
        #expect(try engine.evaluate("(reorder-insert-index 0 1 1)") == .false)
        #expect(try engine.evaluate("(reorder-insert-index 0 1 -1)") == .false)
        #expect(try engine.evaluate("(reorder-insert-index 0 0 1)") == .false)
        // A position outside the scope, or a non-integer one (a malformed
        // payload) degrades to #f rather than erroring on a leader press —
        // cycle-target-id's contract.
        #expect(try engine.evaluate("(reorder-insert-index 4 4 -1)") == .false)
        #expect(try engine.evaluate("(reorder-insert-index -1 4 1)") == .false)
        #expect(try engine.evaluate("(reorder-insert-index #f 4 1)") == .false)
        // A multi-place step is the same formula, no special case.
        #expect(try engine.evaluate("(reorder-insert-index 0 4 2)") == .fixnum(3))
        #expect(try engine.evaluate("(reorder-insert-index 3 4 -2)") == .fixnum(1))
    }

    /// The whole reorder decision as a pure function of a parsed
    /// `<kind>.list` envelope. The load-bearing claim: a tab's position is
    /// its index within **its own workspace's** rows, not within the whole
    /// payload — `tab.list` returns every tab in the session, and `tab.move`
    /// reorders only inside the containing workspace.
    ///
    /// The fixture puts the focused tab at ARRAY index 2 but at SCOPE
    /// position 1 of 3, so a reading that used the array index would answer
    /// insert_index 4 (or, worse, place it among another workspace's tabs);
    /// the scope-local reading answers 3. The ids also carry non-positional
    /// `number`s (`w9:t5` third in its bar) because a tab's `number` is a
    /// stable identity, not its display order.
    @Test func reorderCommandReadsFocusedRowPositionWithinItsOwnScope() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define TABS (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\",\"focused\":false},{\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\",\"focused\":false},{\"tab_id\":\"w9:t2\",\"workspace_id\":\"w9\",\"focused\":true},{\"tab_id\":\"w9:t5\",\"workspace_id\":\"w9\",\"focused\":false},{\"tab_id\":\"w1:t2\",\"workspace_id\":\"w1\",\"focused\":false}]}}"))
          (define (call-of parsed kind step)
            (let ((c (reorder-command kind parsed step)))
              (and c (list (car c)
                           (cdr (assoc "insert_index" (cdr c)))))))
          (define (target-of parsed kind step)
            (let ((c (reorder-command kind parsed step)))
              (and c (cdr (car (cdr c))))))
        """#)
        // Scope position 1 of 3 → later = 3, earlier = 0.
        #expect(try engine.evaluate(#"(equal? (call-of TABS 'tabs 1) '("tab.move" 3))"#) == .true)
        #expect(try engine.evaluate(#"(equal? (call-of TABS 'tabs -1) '("tab.move" 0))"#) == .true)
        // The target is the focused tab's own id, which survives a reorder.
        #expect(try engine.evaluate("(target-of TABS 'tabs 1)") == .string("w9:t2"))
        // The param key is herdr's own field name for the kind.
        #expect(try engine.evaluate(#"(car (car (cdr (reorder-command 'tabs TABS 1))))"#)
                == .string("tab_id"))

        // Spaces are globally ordered — no scope field, so position is the
        // array index. Focused at 0 of 3: later = 2, earlier = #f (the edge).
        try engine.evaluate(#"""
          (define SPACES (json-parse "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w9\",\"focused\":true},{\"workspace_id\":\"w3\",\"focused\":false},{\"workspace_id\":\"w7\",\"focused\":false}]}}"))
        """#)
        #expect(try engine.evaluate(#"(equal? (call-of SPACES 'workspaces 1) '("workspace.move" 2))"#) == .true)
        #expect(try engine.evaluate("(call-of SPACES 'workspaces -1)") == .false)
        #expect(try engine.evaluate("(target-of SPACES 'workspaces 1)") == .string("w9"))
        #expect(try engine.evaluate(#"(car (car (cdr (reorder-command 'workspaces SPACES 1))))"#)
                == .string("workspace_id"))
    }

    /// Every "nothing to do" answers #f, so the op below sends nothing.
    /// Unreachable herdr (#f, ADR-0020's one failure value), a payload with
    /// no `result`, a scope where nothing is focused (herdr's `focused` is
    /// true for exactly one row session-wide, so an unfocused workspace's
    /// tabs are legitimately all false), a focused row missing its id, and a
    /// single-tab scope.
    @Test func reorderCommandDegradesToFalseWhenThereIsNothingToDo() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        #expect(try engine.evaluate("(reorder-command 'tabs #f 1)") == .false)
        #expect(try engine.evaluate(#"(reorder-command 'tabs (json-parse "{\"error\":{\"code\":\"nope\"}}") 1)"#)
                == .false)
        #expect(try engine.evaluate(#"(reorder-command 'tabs (json-parse "{\"result\":{\"tabs\":[]}}") 1)"#)
                == .false)
        // Nothing focused in the payload at all.
        #expect(try engine.evaluate(#"(reorder-command 'tabs (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\",\"focused\":false},{\"tab_id\":\"w1:t2\",\"workspace_id\":\"w1\",\"focused\":false}]}}") 1)"#)
                == .false)
        // The focused row carries no id.
        #expect(try engine.evaluate(#"(reorder-command 'tabs (json-parse "{\"result\":{\"tabs\":[{\"workspace_id\":\"w1\",\"focused\":true},{\"tab_id\":\"w1:t2\",\"workspace_id\":\"w1\",\"focused\":false}]}}") 1)"#)
                == .false)
        // Sole tab in its workspace — even though the payload holds others.
        #expect(try engine.evaluate(#"(reorder-command 'tabs (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\",\"focused\":true},{\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\",\"focused\":false},{\"tab_id\":\"w1:t2\",\"workspace_id\":\"w1\",\"focused\":false}]}}") 1)"#)
                == .false)
    }

    /// The op through both seams: one `<kind>.list` read per press, then
    /// `tab.move` / `workspace.move` on the command seam (a plain
    /// synchronous verb — herdr's move handlers reorder in memory, emit
    /// their event and answer at once, so no send-seam fire-and-forget).
    ///
    /// The claim worth pinning is that the op reads its OWN index fresh per
    /// press rather than reusing the drill's live-list snapshot: the Move
    /// keys re-arm ('next 'self), so a snapshot-reusing op would recompute
    /// one insert_index for a fast `l l` and advance the tab once instead of
    /// twice. The query runner therefore serves a payload that reflects the
    /// first move, and the second press must answer the NEXT index.
    @Test func moveTabReadsItsOwnIndexFreshOnEveryPress() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define reads 0)
          (define calls '())
          ;; Two successive states of one three-tab bar: focused tab first,
          ;; then (after the first move) second.
          (define (bar focused-at)
            (json-parse
              (string-append
                "{\"result\":{\"tabs\":["
                "{\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\",\"focused\":"
                (if (= focused-at 0) "true" "false") "},"
                "{\"tab_id\":\"w9:t2\",\"workspace_id\":\"w9\",\"focused\":"
                (if (= focused-at 1) "true" "false") "},"
                "{\"tab_id\":\"w9:t3\",\"workspace_id\":\"w9\",\"focused\":false}]}}")))
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (set! reads (+ reads 1))
                 (and (string=? method "tab.list") (bar (- reads 1)))))
             (current-herdr-command-runner
               (lambda (method params)
                 (set! calls (cons (cons method params) calls)))))
            (move-tab-right)
            (move-tab-right))
          (define (nth-call n) (list-ref (reverse calls) n))
          (define (insert-of c) (cdr (assoc "insert_index" (cdr c))))
        """#)
        // One list read per press — no cached snapshot.
        #expect(try engine.evaluate("reads") == .fixnum(2))
        #expect(try engine.evaluate("(length calls)") == .fixnum(2))
        #expect(try engine.evaluate("(car (nth-call 0))") == .string("tab.move"))
        // From position 0 → gap 2; from position 1 → gap 3. A snapshot-
        // reusing op would have sent 2 twice.
        #expect(try engine.evaluate("(insert-of (nth-call 0))") == .fixnum(2))
        #expect(try engine.evaluate("(insert-of (nth-call 1))") == .fixnum(3))
        #expect(try engine.evaluate(#"(cdr (assoc "tab_id" (cdr (nth-call 1))))"#)
                == .string("w9:t2"))
    }

    /// At either end the op sends NOTHING — no request herdr would discard,
    /// and (with `'exit-on-unknown` off the direction keys) the Move walk
    /// simply stays armed. Both kinds, both directions, plus the no-focus
    /// case: the query runner is stubbed rather than trusting the host to
    /// lack a live herdr (feedback_no_live_env_mutation_in_tests).
    @Test func moveAtEitherEndOfTheListSendsNoRequest() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define fired? #f)
          (define TABS "{\"result\":{\"tabs\":[{\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\",\"focused\":true},{\"tab_id\":\"w9:t2\",\"workspace_id\":\"w9\",\"focused\":false}]}}")
          (define SPACES "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w1\",\"focused\":false},{\"workspace_id\":\"w9\",\"focused\":true}]}}")
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (json-parse (if (string=? method "tab.list") TABS SPACES))))
             (current-herdr-command-runner
               (lambda (method params) (set! fired? #t)))
             (current-herdr-send-runner
               (lambda (method params) (set! fired? #t))))
            (move-tab-left)     ;; focused tab is already first
            (move-space-down))  ;; focused space is already last
        """#)
        #expect(try engine.evaluate("fired?") == .false)

        // And with herdr unreachable, neither op reaches either seam.
        try engine.evaluate("""
          (parameterize
            ((current-herdr-query-runner (lambda (method params) #f))
             (current-herdr-command-runner (lambda (method params) (set! fired? #t)))
             (current-herdr-send-runner (lambda (method params) (set! fired? #t))))
            (move-tab-left) (move-tab-right)
            (move-space-up) (move-space-down))
        """)
        #expect(try engine.evaluate("fired?") == .false)
    }

    // MARK: - The prefix keystroke ops (k37, ADR-0021)

    /// herdr's three client-side keybindings are (prefix → thunk) ops, so
    /// the prefix reaches every one of them by being an argument — there
    /// is no path to a hardcoded `ctrl+b`. Before k37 Detach had one, and
    /// it failed *silently*: the stray keystrokes land in the pane's
    /// shell rather than a herdr that is not listening for them.
    ///
    /// The emission bodies stay untested by design (send-keystroke is
    /// native with no Scheme seam), so what is pinned is the shape and
    /// the one named default the three share.
    @Test func prefixOpsTakeThePrefixAsTheirOnlyArgument() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        for op in ["copy-mode-op", "scrollback-op", "detach-op"] {
            #expect(try engine.evaluate("(procedure? \(op))") == .true,
                    "\(op) must be exported as a procedure")
            // A non-default prefix, to prove nothing reads a hardcoded one.
            #expect(try engine.evaluate("(procedure? (\(op) '((alt) \"a\")))") == .true,
                    "(\(op) prefix) must yield a thunk")
        }
        #expect(try engine.evaluate("(equal? herdr-default-prefix '((ctrl) \"b\"))") == .true)
    }

    /// Stop Server behaviour: cancel issues nothing; OK sends exactly
    /// `server.stop`. Routed through the same current-dialog-runner seam
    /// already used elsewhere in this file, plus the send seam — no new test
    /// seam.
    ///
    /// It rides `current-herdr-send-runner` rather than the command runner
    /// because herdr acknowledges this one and then exits; whether the reply
    /// outruns the process exit is a race with nothing to win, so the answer
    /// is not asked for.
    @Test func stopServerSendsOnConfirmOnlyAndDoesNothingOnCancel() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser dialogs))")

        // Cancel clicked (stdout doesn't match the "Stop" ok-label) → nothing sent.
        try engine.evaluate("""
          (define fired? #f)
          (parameterize
            ((current-dialog-runner (lambda (cmd cb) (cb 0 "Cancel\\n" "")))
             (current-herdr-send-runner (lambda (method params) (set! fired? #t))))
            (stop-server!))
        """)
        #expect(try engine.evaluate("fired?") == .false)

        // "Stop" clicked → exactly `server.stop`, with no params.
        try engine.evaluate("""
          (define captured #f)
          (parameterize
            ((current-dialog-runner (lambda (cmd cb) (cb 0 "Stop\\n" "")))
             (current-herdr-send-runner
               (lambda (method params) (set! captured (cons method params)))))
            (stop-server!))
        """)
        #expect(try engine.evaluate("(car captured)") == .string("server.stop"))
        #expect(try engine.evaluate("(null? (cdr captured))") == .true)
    }

    // MARK: - Prev/Next ring cycling (leaf prev-next-impl-k10)

    /// The pure ring-step helper (prev-next-nav-k4): wraps at both ends,
    /// seeds from an unfocused (#f) index by step direction, degrades an
    /// empty ring to #f, and resolves trivially for a single row.
    /// Fixture-fed — no live herdr, mirroring next-blocked-pane-id's shape.
    @Test func cycleTargetIdRingSteps() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate("""
          (define TS (list (cons "1" "a") (cons "2" "b") (cons "3" "c")))
        """)
        // Next (step +1): wraps from the last row back to the first.
        #expect(try engine.evaluate("(cycle-target-id TS 0 1)") == .string("b"))
        #expect(try engine.evaluate("(cycle-target-id TS 1 1)") == .string("c"))
        #expect(try engine.evaluate("(cycle-target-id TS 2 1)") == .string("a"))
        // Prev (step -1): wraps from the first row back to the last.
        #expect(try engine.evaluate("(cycle-target-id TS 0 -1)") == .string("c"))
        #expect(try engine.evaluate("(cycle-target-id TS 1 -1)") == .string("a"))
        #expect(try engine.evaluate("(cycle-target-id TS 2 -1)") == .string("b"))
        // #f focused-index (no row focused yet, e.g. before the first
        // render) seeds by direction: next → first row, prev → last row.
        #expect(try engine.evaluate("(cycle-target-id TS #f 1)") == .string("a"))
        #expect(try engine.evaluate("(cycle-target-id TS #f -1)") == .string("c"))
        // An out-of-range focused-index seeds the same way as #f.
        #expect(try engine.evaluate("(cycle-target-id TS 9 1)") == .string("a"))
        #expect(try engine.evaluate("(cycle-target-id TS -1 -1)") == .string("c"))
        // Empty ring → #f regardless of direction or focused-index.
        #expect(try engine.evaluate("(cycle-target-id '() 0 1)") == .false)
        #expect(try engine.evaluate("(cycle-target-id '() #f -1)") == .false)
        // Single row → always itself, from any focused-index or direction.
        try engine.evaluate("(define ONE (list (cons \"1\" \"only\")))")
        #expect(try engine.evaluate("(cycle-target-id ONE 0 1)") == .string("only"))
        #expect(try engine.evaluate("(cycle-target-id ONE 0 -1)") == .string("only"))
        #expect(try engine.evaluate("(cycle-target-id ONE #f 1)") == .string("only"))
    }

    /// Cycling shares the SAME stale-kind guard the digit path uses
    /// (herdr-fast-key-drops-k8): a fast leader→drill→`]` press can reach
    /// the cycling action before THIS kind's on-render-fn ever snapshotted,
    /// so a bare read of the shared current-targets/current-data cell
    /// could silently ring-step another kind's leftover rows. Simulates a
    /// prior Panes render this session, then presses "A" "]" with no
    /// Agents render in between (this harness never opens the overlay): the
    /// kind mismatch must force a fresh `agent list` snapshot before
    /// cycling, exactly like list-digit-range's guard.
    @Test func cyclePressBeforeRenderIgnoresStaleOtherKindEntry() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr)
                  (modaliser blocks herdr-list) (modaliser json))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        // Prior render this session: Panes, one focused row.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "pane.list")
                    (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"focused\":true,\"pane_id\":\"STALE-PANE\",\"tab_id\":\"w1:t1\"}]}}"))
                   (else #f)))))
            (herdr-list-refresh! 'panes #f))
        """#)
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'panes)") == .true)

        try engine.evaluate("(define FIRED '())")
        try engine.evaluate("(modal-activate! \"herdr\" '() F18)")
        try engine.evaluate("(modal-handle-key \"A\")") // Agents drill — no render yet here

        // Cycling ends in a real focus verb, so the WRITE seam is stubbed
        // alongside the read seam. This is the site test-live-herdr-contact-k35
        // was raised for: stubbing the query runner alone let
        // `pane.focus REAL-AGENT-2` travel to the developer's live socket, and
        // the test passed either way — which is precisely how the gap hides.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "agent.list")
                    (json-parse "{\"result\":{\"agents\":[{\"agent\":\"a1\",\"agent_status\":\"idle\",\"focused\":true,\"pane_id\":\"REAL-AGENT-1\"},{\"agent\":\"a2\",\"agent_status\":\"idle\",\"focused\":false,\"pane_id\":\"REAL-AGENT-2\"}]}}"))
                   (else #f))))
             (current-herdr-command-runner
               (lambda (method params)
                 (set! FIRED (cons (cons method params) FIRED))
                 #f)))
            (modal-handle-key "]"))
        """#)

        // The kind mismatch forced a fresh Agents snapshot before cycling —
        // the shared cell no longer belongs to the stale Panes render.
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'agents)") == .true)
        // …and the cycle focused the next agent's PANE, by pane id.
        #expect(try engine.evaluate("(car (car FIRED))") == .string("pane.focus"))
        #expect(try engine.evaluate("(cdr (assoc \"pane_id\" (cdr (car FIRED))))")
                == .string("REAL-AGENT-2"))
        // 'next 'self: firing never pushes/pops — still inside "A".
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"A\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    // MARK: - Jump-target gathering (leaf jump-target-gathering-k25)

    /// jump-pane-target-ids filters a parsed `pane list` fixture to TAB-ID,
    /// preserving JSON (visual) order, and drops non-matching rows.
    @Test func jumpPaneTargetIdsScopesToTabIdPreservingOrder() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"},{\"pane_id\":\"w1:p2\",\"tab_id\":\"w1:t2\"},{\"pane_id\":\"w1:p3\",\"tab_id\":\"w1:t1\"}]}}"))
        """#)
        #expect(try engine.evaluate("(jump-pane-target-ids J \"w1:t1\")")
                == .pair(.string("w1:p1"), .pair(.string("w1:p3"), .null)))
        // #f tab-id degrades to unfiltered (global) — every pane, JSON order.
        #expect(try engine.evaluate("(jump-pane-target-ids J #f)")
                == .pair(.string("w1:p1"),
                         .pair(.string("w1:p2"), .pair(.string("w1:p3"), .null))))
    }

    /// A #f parse (herdr unreachable) or a result with no `panes` array
    /// degrades to '() rather than erroring — the same non-negotiable a
    /// render-path extractor needs everywhere else in this file.
    @Test func jumpPaneTargetIdsDegradesToEmptyOnMissingInput() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        #expect(try engine.evaluate("(null? (jump-pane-target-ids #f \"w1:t1\"))") == .true)
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{}}"))
        """#)
        #expect(try engine.evaluate("(null? (jump-pane-target-ids J \"w1:t1\"))") == .true)
    }

    /// parse-ui-layout over a fixture built from docs/specs/herdr-ui-layout.md's
    /// own worked example (extended with a second entry per axis to prove
    /// order preservation, not just single-element extraction): the three
    /// ui.layout-sourced axes come back as id lists in JSON (visual) order,
    /// keyed on the same public ids the list methods use.
    @Test func parseUiLayoutExtractsThreeAxesInVisualOrder() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"type\":\"ui_layout\",\"layout\":\"desktop\",\"obscured\":false,\"canvas\":{\"width\":273,\"height\":74},\"sidebar\":{\"mode\":\"expanded\",\"rect\":{\"x\":0,\"y\":0,\"width\":36,\"height\":74},\"workspaces\":[{\"workspace_id\":\"w_1\",\"focused\":true,\"rect\":{\"x\":0,\"y\":2,\"width\":35,\"height\":2}},{\"workspace_id\":\"w_2\",\"focused\":false,\"rect\":{\"x\":0,\"y\":4,\"width\":35,\"height\":2}}],\"agents\":[{\"pane_id\":\"w_1:p7\",\"rect\":{\"x\":0,\"y\":40,\"width\":35,\"height\":1}},{\"pane_id\":\"w_2:p3\",\"rect\":{\"x\":0,\"y\":41,\"width\":35,\"height\":1}}]},\"tab_bar\":{\"rect\":{\"x\":36,\"y\":0,\"width\":237,\"height\":1},\"workspace_id\":\"w_1\",\"tabs\":[{\"tab_id\":\"w_1:t2\",\"focused\":true,\"rect\":{\"x\":36,\"y\":0,\"width\":14,\"height\":1}},{\"tab_id\":\"w_1:t3\",\"focused\":false,\"rect\":{\"x\":50,\"y\":0,\"width\":14,\"height\":1}}]}}}"))
          (define R (parse-ui-layout J))
        """#)
        #expect(try engine.evaluate("(cdr (assoc 'workspaces R))")
                == .pair(.string("w_1"), .pair(.string("w_2"), .null)))
        #expect(try engine.evaluate("(cdr (assoc 'agents R))")
                == .pair(.string("w_1:p7"), .pair(.string("w_2:p3"), .null)))
        #expect(try engine.evaluate("(cdr (assoc 'tabs R))")
                == .pair(.string("w_1:t2"), .pair(.string("w_1:t3"), .null)))
    }

    /// Degradation is explicit (docs/specs/herdr-ui-layout.md "Sidebar modes" /
    /// "Tab bar absence"): a hidden sidebar (empty workspace/agent arrays) and
    /// an absent tab bar (zero rect, empty tabs) both drop their axes to '()
    /// with no error — mirroring the mobile-layout / no-ui.layout-support
    /// case, not just a genuinely empty desktop UI. A totally #f parse (the
    /// "any error means not supported" contract) degrades every axis too.
    @Test func parseUiLayoutDegradesHiddenSectionsToEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"layout\":\"desktop\",\"sidebar\":{\"mode\":\"hidden\",\"rect\":{\"x\":0,\"y\":0,\"width\":0,\"height\":74},\"workspaces\":[],\"agents\":[]},\"tab_bar\":{\"rect\":{\"x\":0,\"y\":0,\"width\":0,\"height\":0},\"workspace_id\":\"w_1\",\"tabs\":[]}}}"))
          (define R (parse-ui-layout J))
        """#)
        #expect(try engine.evaluate("(null? (cdr (assoc 'workspaces R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'agents R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'tabs R)))") == .true)

        // No ui.layout support at all — a #f query result.
        try engine.evaluate("(define R2 (parse-ui-layout #f))")
        #expect(try engine.evaluate("(null? (cdr (assoc 'workspaces R2)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'agents R2)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'tabs R2)))") == .true)
    }

    // MARK: - Mini-chip geometry (leaf mini-chip-geometry-k31)

    /// The three ui-layout-*-chip-entries functions over the SAME worked
    /// example fixture as parseUiLayoutExtractsThreeAxesInVisualOrder — canvas
    /// 273×74 against a 2730×740 host frame is an exact ×10 cell→pixel scale
    /// with no rounding, so every expected pixel value is a clean multiple of
    /// the cell's (x y width height). Host offset (1000, 2000) proves the
    /// translation, not just the scale. A bogus extra workspace target
    /// ("w_9", not drawn — scrolled away or folded) is dropped rather than
    /// erroring, mirroring herdr-chip-entries' off-tab-pane behaviour.
    @Test func uiLayoutChipEntriesSynthesisesCanvasRelativeRects() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"type\":\"ui_layout\",\"layout\":\"desktop\",\"obscured\":false,\"canvas\":{\"width\":273,\"height\":74},\"sidebar\":{\"mode\":\"expanded\",\"rect\":{\"x\":0,\"y\":0,\"width\":36,\"height\":74},\"workspaces\":[{\"workspace_id\":\"w_1\",\"focused\":true,\"rect\":{\"x\":0,\"y\":2,\"width\":35,\"height\":2}},{\"workspace_id\":\"w_2\",\"focused\":false,\"rect\":{\"x\":0,\"y\":4,\"width\":35,\"height\":2}}],\"agents\":[{\"pane_id\":\"w_1:p7\",\"rect\":{\"x\":0,\"y\":40,\"width\":35,\"height\":1}},{\"pane_id\":\"w_2:p3\",\"rect\":{\"x\":0,\"y\":41,\"width\":35,\"height\":1}}]},\"tab_bar\":{\"rect\":{\"x\":36,\"y\":0,\"width\":237,\"height\":1},\"workspace_id\":\"w_1\",\"tabs\":[{\"tab_id\":\"w_1:t2\",\"focused\":true,\"rect\":{\"x\":36,\"y\":0,\"width\":14,\"height\":1}},{\"tab_id\":\"w_1:t3\",\"focused\":false,\"rect\":{\"x\":50,\"y\":0,\"width\":14,\"height\":1}}]}}}"))
          (define HOST (list (cons 'x 1000) (cons 'y 2000) (cons 'w 2730) (cons 'h 740)))
          (define WS (ui-layout-workspace-chip-entries
                       (list (cons "a" "w_1") (cons "b" "w_2") (cons "c" "w_9")) J HOST))
          (define AG (ui-layout-agent-chip-entries
                       (list (cons "a" "w_1:p7") (cons "b" "w_2:p3")) J HOST))
          (define TB (ui-layout-tab-chip-entries
                       (list (cons "a" "w_1:t2") (cons "b" "w_1:t3")) J HOST))
          (define (rect entries lab key) (cdr (assoc key (cdr (assoc lab entries)))))
        """#)
        // The undrawn "w_9" target yields no chip — only the two real ones.
        #expect(try engine.evaluate("(length WS)") == .fixnum(2))
        #expect(try engine.evaluate("(rect WS \"a\" 'x)") == .fixnum(1000))
        #expect(try engine.evaluate("(rect WS \"a\" 'y)") == .fixnum(2020))
        #expect(try engine.evaluate("(rect WS \"a\" 'w)") == .fixnum(350))
        #expect(try engine.evaluate("(rect WS \"a\" 'h)") == .fixnum(20))
        #expect(try engine.evaluate("(rect WS \"b\" 'y)") == .fixnum(2040))

        #expect(try engine.evaluate("(rect AG \"a\" 'y)") == .fixnum(2400))
        #expect(try engine.evaluate("(rect AG \"b\" 'y)") == .fixnum(2410))
        #expect(try engine.evaluate("(rect AG \"a\" 'w)") == .fixnum(350))
        #expect(try engine.evaluate("(rect AG \"a\" 'h)") == .fixnum(10))

        #expect(try engine.evaluate("(rect TB \"a\" 'x)") == .fixnum(1360))
        #expect(try engine.evaluate("(rect TB \"b\" 'x)") == .fixnum(1500))
        #expect(try engine.evaluate("(rect TB \"a\" 'y)") == .fixnum(2000))
        #expect(try engine.evaluate("(rect TB \"a\" 'w)") == .fixnum(140))

        // Same (label . ((handle . #f)(x)(y)(w)(h))) shape herdr-chip-entries
        // produces — feedable straight into ax-target-hints.
        #expect(try engine.evaluate("(cdr (assoc 'handle (cdr (assoc \"a\" WS))))") == .false)
    }

    /// Two rows that touch in cell-space (one's bottom edge is the next's
    /// top edge — the common case for a packed sidebar list) must touch in
    /// pixel-space too, for ANY host size, not just ones where the cell-to-
    /// pixel ratio happens to land on a whole number
    /// (mini-chip-size-and-label-anchor-k38's live dogfooding: visible
    /// mini-chip collisions at the real live host size). Rounding each
    /// edge separately and deriving size as their difference guarantees
    /// this by construction — rounding position and size independently
    /// does not: several of the host heights swept here (100, 150, 200,
    /// 250) are verified (by direct calculation) to gap/overlap under the
    /// old independent-rounding approach, so this is a real regression
    /// guard, not a vacuously-true property.
    @Test func uiLayoutChipEntriesAdjacentRowsNeverGapOrOverlap() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define J (json-parse "{\"result\":{\"canvas\":{\"width\":425,\"height\":116},\"sidebar\":{\"agents\":[{\"pane_id\":\"a1\",\"rect\":{\"x\":0,\"y\":61,\"width\":25,\"height\":2}},{\"pane_id\":\"a2\",\"rect\":{\"x\":0,\"y\":63,\"width\":25,\"height\":2}}]}}}"))
          (define (row1-bottom-meets-row2-top host-h)
            (let* ((host (list (cons 'x 0) (cons 'y 0) (cons 'w 200) (cons 'h host-h)))
                   (entries (ui-layout-agent-chip-entries
                              (list (cons "a" "a1") (cons "b" "a2")) J host))
                   (r1 (cdr (assoc "a" entries)))
                   (r2 (cdr (assoc "b" entries))))
              (= (+ (cdr (assoc 'y r1)) (cdr (assoc 'h r1))) (cdr (assoc 'y r2)))))
        """#)
        for hostHeight in [100, 150, 200, 201, 250, 299, 300, 301, 333, 400, 512, 1000] {
            #expect(
                try engine.evaluate("(row1-bottom-meets-row2-top \(hostHeight))") == .true,
                "adjacent agent rows gap/overlap at host height \(hostHeight)"
            )
        }
    }

    /// Degrade-to-empty (docs/specs/herdr-ui-layout.md "Compatibility and
    /// probing" — any error means "not supported"): a totally #f parse (no
    /// ui.layout support), a response missing the `canvas` field entirely, a
    /// malformed canvas (non-positive width), and a missing host frame (no
    /// live iTerm AXScrollArea) all degrade to '() rather than raising.
    @Test func uiLayoutChipEntriesDegradesToEmptyOnMissingOrMalformedInput() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define TARGETS (list (cons "a" "w_1")))
          (define HOST (list (cons 'x 0) (cons 'y 0) (cons 'w 2730) (cons 'h 740)))
          (define NO-CANVAS (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\",\"rect\":{\"x\":0,\"y\":2,\"width\":35,\"height\":2}}]}}}"))
          (define BAD-CANVAS (json-parse "{\"result\":{\"canvas\":{\"width\":0,\"height\":74},\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\",\"rect\":{\"x\":0,\"y\":2,\"width\":35,\"height\":2}}]}}}"))
          (define OK (json-parse "{\"result\":{\"canvas\":{\"width\":273,\"height\":74},\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\",\"rect\":{\"x\":0,\"y\":2,\"width\":35,\"height\":2}}]}}}"))
        """#)
        // No ui.layout support at all.
        #expect(try engine.evaluate("(null? (ui-layout-workspace-chip-entries TARGETS #f HOST))") == .true)
        // canvas key absent.
        #expect(try engine.evaluate("(null? (ui-layout-workspace-chip-entries TARGETS NO-CANVAS HOST))") == .true)
        // canvas present but non-positive (would divide by zero).
        #expect(try engine.evaluate("(null? (ui-layout-workspace-chip-entries TARGETS BAD-CANVAS HOST))") == .true)
        // Valid response, but no host frame (iTerm AX query returned nothing).
        #expect(try engine.evaluate("(null? (ui-layout-workspace-chip-entries TARGETS OK #f))") == .true)
    }

    /// gather-jump-targets orders entries in stable-axis order (spaces →
    /// agents → tabs → panes, jump-label-axis-pools-k43 — revised from the
    /// original panes-first global priority so the volatile current-tab
    /// pane count can never shift a space/agent label), visual order
    /// preserved within each axis, each entry carrying (kind . id) enough
    /// to identify the target and later dispatch its focus verb.
    @Test func gatherJumpTargetsOrdersByAxisPriority() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define R (gather-jump-targets
                       (list "w1:p1" "w1:p2")
                       (list "w_1" "w_2")
                       (list "w1:p9")
                       (list "w1:t2")))
          (define (entry-kind i) (cdr (assoc 'kind (list-ref R i))))
          (define (entry-id i)   (cdr (assoc 'id   (list-ref R i))))
        """#)
        #expect(try engine.evaluate("(length R)") == .fixnum(6))
        // Kind comparison stays inside Scheme (equal? over a quoted symbol
        // list) rather than reconstructing symbol Exprs on the Swift side.
        #expect(try engine.evaluate("""
          (equal? (list (entry-kind 0) (entry-kind 1) (entry-kind 2)
                         (entry-kind 3) (entry-kind 4) (entry-kind 5))
                  '(workspaces workspaces agents tabs panes panes))
          """) == .true)
        #expect(try engine.evaluate("(list (entry-id 0) (entry-id 1) (entry-id 2) (entry-id 3) (entry-id 4) (entry-id 5))")
                == .pair(.string("w_1"),
                         .pair(.string("w_2"),
                         .pair(.string("w1:p9"),
                         .pair(.string("w1:t2"),
                         .pair(.string("w1:p1"),
                         .pair(.string("w1:p2"), .null)))))))
    }

    /// No same-destination collapsing (docs/specs/herdr-jump-navigation.md
    /// "Jump space scope", include-focused-targets-for-stability-k39): an
    /// agent whose pane is already listed under panes still gets its OWN
    /// entry — every target from every axis survives, even when two name
    /// the same underlying pane_id. Stable-axis order is preserved
    /// (agents before panes).
    @Test func gatherJumpTargetsKeepsEveryTargetAcrossPanesAndAgents() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define R (gather-jump-targets
                       (list "w1:p1")
                       '()
                       (list "w1:p1" "w1:p9")
                       '()))
        """#)
        #expect(try engine.evaluate("(length R)") == .fixnum(3))
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind (car R))) 'agents)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'id (car R)))") == .string("w1:p1"))
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind (cadr R))) 'agents)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'id (cadr R)))") == .string("w1:p9"))
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind (caddr R))) 'panes)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'id (caddr R)))") == .string("w1:p1"))
    }

    /// All four axes empty degrades to an empty target list, no error.
    @Test func gatherJumpTargetsAllAxesEmptyYieldsEmptyList() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        #expect(try engine.evaluate("(null? (gather-jump-targets '() '() '() '()))") == .true)
    }

    /// No ui.layout support (or a herdr without it) drops workspaces/agents/
    /// tabs to '() while the panes axis — which needs no ui.layout at all —
    /// still produces a valid, panes-only target list. This is the
    /// degradation docs/specs/herdr-jump-navigation.md "Geometry" promises:
    /// jump keys still work with no ui.layout, only mini-chips don't paint.
    @Test func gatherJumpTargetsPanesOnlyStillValidWithoutUiLayout() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define AXES (parse-ui-layout #f))
          (define R (gather-jump-targets
                       (list "w1:p1" "w1:p2")
                       (cdr (assoc 'workspaces AXES))
                       (cdr (assoc 'agents AXES))
                       (cdr (assoc 'tabs AXES))))
        """#)
        #expect(try engine.evaluate("(length R)") == .fixnum(2))
        #expect(try engine.evaluate("""
          (equal? (map (lambda (e) (cdr (assoc 'kind e))) R) '(panes panes))
          """) == .true)
    }

    // MARK: - Jump dispatch wiring (leaf jump-dispatch-wiring-k26)

    /// herdr-jump-provider assigns each axis's single-key label from its
    /// OWN reserved pool (jump-label-axis-pools-k43,
    /// docs/specs/herdr-jump-navigation.md "Jump labels"): panes from
    /// `h j k l ;`, spaces from `a s d f g`, agents first from the shared
    /// top row `q w e r t y u i o p`, tabs from whatever that
    /// leaves (here, one agent target consumes "q", so the sole tab target
    /// gets "w" — the next letter in the shared pool). Each assigned label
    /// dispatches through the kind-appropriate focus verb, captured here
    /// via current-herdr-jump-focus-runner (the test seam standing in for
    /// a real herdr-cmd socket call — see its own docstring, mirroring
    /// current-herdr-query-runner/current-herdr-send-runner's rationale).
    /// Firing is Terminal: the modal exits (docs/specs/herdr-jump-
    /// navigation.md "Narrowing"), so each kind is exercised in its own
    /// fresh activation round.
    @Test func herdrJumpProviderDispatchesEachAxisKindsSingleKeyFocusVerb() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr) (modaliser json)
                  (only (modaliser blocks herdr-list) current-herdr-host-frame)
                  (modaliser muxes herdr-socket))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("""
          (define captured '())
        """)
        // current-herdr-host-frame closes the PAINT pipeline's own AX seam
        // (herdr-jump-tests-live-ax-k50): activation can reach
        // herdr-paint-chip-targets!/herdr-paint-ui-layout-chip-targets!,
        // whose geometry runs a live-AX iTerm scan that SIGBUS-es a
        // cooperative-pool test thread. Their `pane.layout`/`ui.layout`
        // queries ride the SAME current-herdr-query-runner stubbed below
        // (list-block-query-cutover-k32 collapsed the two seams into one),
        // so an unlisted method already answers #f; the host-frame stub is
        // what guarantees no AX call even when a method IS answered. These
        // tests exercise dispatch, never painting.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "pane.current")
                    (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                   ((string=? method "pane.list")
                    (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"}]}}"))
                   ((string=? method "ui.layout")
                    (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_2\"}],\"agents\":[{\"pane_id\":\"w1:p9\"}]},\"tab_bar\":{\"tabs\":[{\"tab_id\":\"w1:t3\"}]}}}"))
                   (else #f))))
             (current-herdr-host-frame (lambda (total-w total-h) #f))
             (current-herdr-jump-focus-runner
               (lambda (kind id) (set! captured (cons (cons kind id) captured)))))
            (modal-activate! "herdr" '() F18)
            (modal-handle-key "h")
            (modal-activate! "herdr" '() F18)
            (modal-handle-key "a")
            (modal-activate! "herdr" '() F18)
            (modal-handle-key "q")
            (modal-activate! "herdr" '() F18)
            (modal-handle-key "w"))
        """#)
        #expect(try engine.evaluate("(length captured)") == .fixnum(4))
        #expect(try engine.evaluate("(if (member (cons 'panes \"w1:p1\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'workspaces \"w_2\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'agents \"w1:p9\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'tabs \"w1:t3\") captured) #t #f)") == .true)
    }

    /// PINNED REGRESSION (herdr-pane-switching-regression-k25, ADR-0020).
    ///
    /// The bug: `focus-pane-by-id` issued `agent focus <pane_id>`, which in
    /// herdr 0.7.5 resolves ONLY agent panes — a plain shell or file-browser
    /// pane came back `{"error":{"code":"agent_not_found"}}` and never
    /// focused. Every top-level pane jump at a non-agent pane silently did
    /// nothing.
    ///
    /// The test that would have caught it has to assert the verb that
    /// reaches the wire, so it captures at current-herdr-command-runner —
    /// one level BELOW current-herdr-jump-focus-runner, which the sibling
    /// test above uses and which stops at (kind . id) pairs, exactly the
    /// altitude at which `agent focus` and `pane.focus` are
    /// indistinguishable. That gap is why this shipped.
    ///
    /// The fixture pane carries no `agent` field: it is precisely the
    /// non-agent case that used to fail. What the test pins is the
    /// invariant the fix establishes — the PANES axis focuses by pane id
    /// (`pane.focus`), never through the agents axis's `agent.focus`.
    @Test func paneJumpFocusesNonAgentPaneViaPaneFocusNotAgentFocus() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr) (modaliser json)
                  (only (modaliser blocks herdr-list) current-herdr-host-frame)
                  (modaliser muxes herdr-socket))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("""
          (define fired '())
        """)
        // current-herdr-jump-focus-runner is deliberately NOT stubbed here:
        // the real focus verb must run so the method it picks is observable.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner
               (lambda (method params)
                 (cond
                   ((string=? method "pane.current")
                    (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                   ((string=? method "pane.list")
                    (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p7\",\"tab_id\":\"w1:t1\"}]}}"))
                   (else #f))))
             (current-herdr-host-frame (lambda (total-w total-h) #f))
             (current-herdr-command-runner
               (lambda (method params)
                 (set! fired (cons (cons method params) fired)))))
            (modal-activate! "herdr" '() F18)
            (modal-handle-key "h"))
        """#)
        #expect(try engine.evaluate("(length fired)") == .fixnum(1))
        #expect(try engine.evaluate("(car (car fired))") == .makeString("pane.focus"))
        #expect(try engine.evaluate("""
          (equal? (cdr (car fired)) '(("pane_id" . "w1:p7")))
        """) == .true)
    }

    /// Two-key narrowing end to end: 24 tab-scoped panes exceed the panes
    /// pool's ("h" "j" "k" "l" ";", jump-label-axis-pools-k43) 5 single-key
    /// slots, so jump-labels-assign escalates leader "h" (the pool's own
    /// first letter — escalation never borrows another axis's pool) to
    /// two-key duty: p1..p4 keep the remaining singles "j" "k" "l" ";" in
    /// order, p5 gets "ha", p6 gets "hs" (leader "h", second-alphabet order
    /// "a" then "s" — the shared 20-key union of the pools). 24 panes, not
    /// 25: that is one promoted leader's exact capacity (4 singles + 20
    /// two-keys); a 25th would promote leader "j" too, reshuffling the
    /// singles. Pressing "h" narrows
    /// (modal stays active, modal-current-path becomes ("h")); a second
    /// key fires the matching target (Terminal); backspace after the
    /// leader un-narrows back to the top level (modal-current-path empty,
    /// modal still active), and the root's OWN single-key edges work again
    /// (here "k" -> p2, the second remaining single) — proving the herdr
    /// entry node's provider re-runs (a fresh Visit, not stale state) on
    /// return, per docs/specs/fsm-graph.md "Runtime semantics".
    @Test func herdrJumpProviderTwoKeyLabelNarrowsThenFiresAndBackspaceUnNarrows() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr) (modaliser json)
                  (only (modaliser blocks herdr-list) current-herdr-host-frame)
                  (modaliser muxes herdr-socket))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("""
          (define captured '())
        """)
        let paneEntries = (1...24).map { "{\"pane_id\":\"w1:p\($0)\",\"tab_id\":\"w1:t1\"}" }.joined(separator: ",")
        let paneListEscaped = "{\"result\":{\"panes\":[\(paneEntries)]}}"
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Every mutating action below runs inside its own `parameterize` +
        // `engine.evaluate` call, and every subsequent state check
        // (modal-current-path / modal-active?) runs in a LATER, separate
        // `engine.evaluate` call — reading a plain exported mutable global
        // (not a thunk) back-to-back with the action that just mutated it,
        // in the SAME evaluate call, sees a stale pre-call snapshot under
        // LispKit (mirrors this library's own modal-stack doc comment:
        // "reading … directly from .scm files loaded outside any library
        // captures a stale binding"); splitting into separate calls is
        // exactly how every other test in this file already reads
        // modal-current-path/modal-active? after a modal-handle-key call.
        //
        // current-herdr-host-frame closes the PAINT pipeline's own AX seam
        // (herdr-jump-tests-live-ax-k50). Since defer-chips-to-overlay-k33
        // the chip hooks are presentation-gated, so with no overlay host
        // installed run-on-enter never fires here at all — the stub is now
        // belt-and-braces rather than the sole guard, and stays because the
        // seam it closes is real: were the hook to run,
        // paint-jump-chips-narrowed! would fire synchronously inside
        // modal-handle-key, and against a live herdr its `pane.layout`/
        // `ui.layout` queries would return a real canvas, whose host-frame
        // lookup then scans the live desktop's AX tree and SIGBUS-es the
        // cooperative-pool test thread. Those queries ride the SAME
        // current-herdr-query-runner stubbed below
        // (list-block-query-cutover-k32 collapsed the two seams into one);
        // the host-frame stub is what guarantees no AX call regardless.
        // This test exercises narrowing dispatch, never painting.
        func act(_ body: String) throws {
            try engine.evaluate(#"""
              (parameterize
                ((current-herdr-query-runner
                   (lambda (method params)
                     (cond
                       ((string=? method "pane.current")
                        (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                       ((string=? method "pane.list")
                        (json-parse "\#(paneListEscaped)"))
                       (else #f))))
                 (current-herdr-host-frame (lambda (total-w total-h) #f))
                 (current-herdr-jump-focus-runner
                   (lambda (kind id) (set! captured (cons (cons kind id) captured)))))
            """# + body + ")")
        }

        // Round 1: leader "h" narrows; a second "a" fires p5 ("ha").
        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "h")"#)
        #expect(try engine.evaluate("(equal? modal-current-path (list \"h\"))") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        try act(#"(modal-handle-key "a")"#)
        #expect(try engine.evaluate("modal-active?") == .false)

        // Round 2: leader "h" then second key "s" fires p6 ("hs").
        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "h") (modal-handle-key "s")"#)
        #expect(try engine.evaluate("modal-active?") == .false)

        // Round 3: leader "h" then backspace un-narrows back to the top
        // level; the root's OWN single-key edge ("k" -> p2, the pool's
        // second remaining single) still fires afterward — proving the
        // provider re-ran (a fresh Visit), not stale state left over from
        // before narrowing.
        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "h") (modal-step-back)"#)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        try act(#"(modal-handle-key "k")"#)

        #expect(try engine.evaluate("(length captured)") == .fixnum(3))
        #expect(try engine.evaluate("(if (member (cons 'panes \"w1:p5\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'panes \"w1:p6\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'panes \"w1:p2\") captured) #t #f)") == .true)
    }

    /// No same-destination collapsing, through the FULL provider pipeline
    /// (not just gather-jump-targets' own pure-function tests above):
    /// an agent whose pane_id duplicates an already-listed pane still gets
    /// its OWN target and its OWN label before label assignment runs. With
    /// 3 resulting targets — "h" panes/w1:p1 (panes' own pool), "q"
    /// agents/w1:p1 (a redundant path to the SAME pane, shared-pool order),
    /// "w" agents/w1:p9 (shared-pool order) — all three are independently
    /// live keys.
    @Test func herdrJumpProviderKeepsEveryTargetAsIndependentLiveKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr) (modaliser json)
                  (only (modaliser blocks herdr-list) current-herdr-host-frame)
                  (modaliser muxes herdr-socket))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("""
          (define captured '())
        """)
        // Paint-pipeline seams stubbed to "unreachable" — see
        // herdrJumpProviderDispatchesEachAxisKindsSingleKeyFocusVerb's
        // comment (herdr-jump-tests-live-ax-k50).
        func act(_ body: String) throws {
            try engine.evaluate(#"""
              (parameterize
                ((current-herdr-query-runner
                   (lambda (method params)
                     (cond
                       ((string=? method "pane.current")
                        (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                       ((string=? method "pane.list")
                        (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"}]}}"))
                       ((string=? method "ui.layout")
                        (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[],\"agents\":[{\"pane_id\":\"w1:p1\"},{\"pane_id\":\"w1:p9\"}]},\"tab_bar\":{\"tabs\":[]}}}"))
                       (else #f))))
                 (current-herdr-host-frame (lambda (total-w total-h) #f))
                 (current-herdr-jump-focus-runner
                   (lambda (kind id) (set! captured (cons (cons kind id) captured)))))
            """# + body + ")")
        }

        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "h")"#)
        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "q")"#)
        try act(#"(modal-activate! "herdr" '() F18) (modal-handle-key "w")"#)

        #expect(try engine.evaluate("(length captured)") == .fixnum(3))
        #expect(try engine.evaluate("(if (member (cons 'panes \"w1:p1\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'agents \"w1:p1\") captured) #t #f)") == .true)
        #expect(try engine.evaluate("(if (member (cons 'agents \"w1:p9\") captured) #t #f)") == .true)
    }

    /// Stability contract (jump-label-axis-pools-k43, docs/specs/herdr-
    /// jump-navigation.md "Jump labels"): an axis's labels are a pure
    /// function of its OWN visible list. Panes and spaces each own a
    /// dedicated pool, so growing EITHER of the other two axes must never
    /// shift their labels. Agents and tabs share the remainder pool with a
    /// ONE-DIRECTIONAL coupling: growing agents shifts tabs' labels
    /// (agents assigns first, from the front of the shared pool), but
    /// growing tabs never shifts agents'. Exercised directly through
    /// herdr-jump-provider (fixture-only, no activation) with small counts
    /// so no axis escalates past a single key, keeping every assigned
    /// label a direct edge this test can read straight off the RESULT.
    @Test func herdrJumpProviderLabelsAreStablePerAxisWithOneWayAgentsToTabsCoupling() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser dsl) (modaliser fsm) (modaliser muxes herdr)
                  (modaliser json) (modaliser util))
        """)
        try engine.evaluate(#"""
          (define (label-for id edges)
            (let ((e (find (lambda (e) (equal? (cdr (assoc 'target e)) id)) edges)))
              (and e (cdr (assoc 'trigger e)))))
          (define (edges-of result) (cdr (assoc 'edges result)))
        """#)

        // Scenario A: 1 space, 2 agents, 1 tab, 1 pane.
        try engine.evaluate(#"""
          (define RESULT-A
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (cond
                     ((string=? method "pane.current")
                      (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                     ((string=? method "pane.list")
                      (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"}]}}"))
                     ((string=? method "ui.layout")
                      (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\"}],\"agents\":[{\"pane_id\":\"w1:p1\"},{\"pane_id\":\"w1:p2\"}]},\"tab_bar\":{\"tabs\":[{\"tab_id\":\"w1:t1\"}]}}}"))
                     (else #f)))))
              (herdr-jump-provider)))
        """#)
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/panes/w1:p1\" (edges-of RESULT-A))") == .string("h"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/workspaces/w_1\" (edges-of RESULT-A))") == .string("a"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p1\" (edges-of RESULT-A))") == .string("q"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p2\" (edges-of RESULT-A))") == .string("w"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/tabs/w1:t1\" (edges-of RESULT-A))") == .string("e"))

        // Scenario B: SAME space/agents, tabs grown 1 -> 3. Panes/spaces/
        // agents must be untouched; w1:t1 keeps "e" (agents unchanged, so
        // the shared pool still hands tabs the same starting letter), the
        // two new tabs continue "r" "t".
        try engine.evaluate(#"""
          (define RESULT-B
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (cond
                     ((string=? method "pane.current")
                      (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                     ((string=? method "pane.list")
                      (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"}]}}"))
                     ((string=? method "ui.layout")
                      (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\"}],\"agents\":[{\"pane_id\":\"w1:p1\"},{\"pane_id\":\"w1:p2\"}]},\"tab_bar\":{\"tabs\":[{\"tab_id\":\"w1:t1\"},{\"tab_id\":\"w1:t2\"},{\"tab_id\":\"w1:t3\"}]}}}"))
                     (else #f)))))
              (herdr-jump-provider)))
        """#)
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/panes/w1:p1\" (edges-of RESULT-B))") == .string("h"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/workspaces/w_1\" (edges-of RESULT-B))") == .string("a"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p1\" (edges-of RESULT-B))") == .string("q"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p2\" (edges-of RESULT-B))") == .string("w"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/tabs/w1:t1\" (edges-of RESULT-B))") == .string("e"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/tabs/w1:t2\" (edges-of RESULT-B))") == .string("r"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/tabs/w1:t3\" (edges-of RESULT-B))") == .string("t"))

        // Scenario C: SAME space, agents grown 2 -> 3, tabs back to 1.
        // Panes/spaces stay untouched; agents claim one more shared-pool
        // letter ("e"), so w1:t1's label shifts from "e" (Scenarios A/B) to
        // "r" — the one coupling this leaf's pools deliberately keep
        // (agents → tabs, never tabs → agents, never touching panes/spaces).
        try engine.evaluate(#"""
          (define RESULT-C
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (cond
                     ((string=? method "pane.current")
                      (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                     ((string=? method "pane.list")
                      (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"}]}}"))
                     ((string=? method "ui.layout")
                      (json-parse "{\"result\":{\"sidebar\":{\"workspaces\":[{\"workspace_id\":\"w_1\"}],\"agents\":[{\"pane_id\":\"w1:p1\"},{\"pane_id\":\"w1:p2\"},{\"pane_id\":\"w1:p3\"}]},\"tab_bar\":{\"tabs\":[{\"tab_id\":\"w1:t1\"}]}}}"))
                     (else #f)))))
              (herdr-jump-provider)))
        """#)
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/panes/w1:p1\" (edges-of RESULT-C))") == .string("h"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/workspaces/w_1\" (edges-of RESULT-C))") == .string("a"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p1\" (edges-of RESULT-C))") == .string("q"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p2\" (edges-of RESULT-C))") == .string("w"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/agents/w1:p3\" (edges-of RESULT-C))") == .string("e"))
        #expect(try engine.evaluate("(label-for \"herdr-jump-target/tabs/w1:t1\" (edges-of RESULT-C))") == .string("r"))
    }

    // MARK: - Full-size chip painting (leaf full-size-chip-letter-labels-k27)

    /// jump-panes-chip-targets is the pure reshape at the heart of this
    /// leaf: jump-labels-assign's ASSIGNED list ((label . target) …,
    /// target = ((kind . KIND) (id . ID))) filtered to the panes-kind
    /// subset only and reshaped to herdr-chip-entries' (label . pane-id)
    /// shape. Non-panes kinds (workspaces/agents/tabs — mini-chips-k7's
    /// job) and an unassigned (#f label) target are both dropped; order
    /// is preserved.
    @Test func jumpPanesChipTargetsFiltersToPanesKindReshaped() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "a" (list (cons 'kind 'panes) (cons 'id "w1:p1")))
                  (cons "d" (list (cons 'kind 'workspaces) (cons 'id "w_2")))
                  (cons "e" (list (cons 'kind 'panes) (cons 'id "w1:p2")))
                  (cons #f  (list (cons 'kind 'panes) (cons 'id "w1:p3")))
                  (cons "f" (list (cons 'kind 'agents) (cons 'id "w1:p9")))))
          (define R (jump-panes-chip-targets ASSIGNED))
        """#)
        #expect(try engine.evaluate(
            "(equal? R (list (cons \"a\" \"w1:p1\") (cons \"e\" \"w1:p2\")))") == .true)
    }

    // MARK: - Mini-chip painting (leaf mini-chip-painting-k32)

    /// jump-targets-of-kind generalises jump-panes-chip-targets by KIND
    /// (mini-chip-painting-k32) so the three ui.layout-sourced kinds reuse
    /// the SAME reshape rather than three near-identical copies — proved
    /// here against 'workspaces; jump-panes-chip-targets (tested above) is
    /// this function's 'panes specialisation and is unchanged.
    @Test func jumpTargetsOfKindFiltersToGivenKindReshaped() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "a" (list (cons 'kind 'panes) (cons 'id "w1:p1")))
                  (cons "d" (list (cons 'kind 'workspaces) (cons 'id "w_2")))
                  (cons "e" (list (cons 'kind 'workspaces) (cons 'id "w_3")))
                  (cons #f  (list (cons 'kind 'workspaces) (cons 'id "w_4")))
                  (cons "f" (list (cons 'kind 'agents) (cons 'id "w1:p9")))))
          (define R (jump-targets-of-kind 'workspaces ASSIGNED))
        """#)
        #expect(try engine.evaluate(
            "(equal? R (list (cons \"d\" \"w_2\") (cons \"e\" \"w_3\")))") == .true)
    }

    // MARK: - Narrowing-dim chip painting (leaf narrowing-dim-state-k30)

    /// jump-narrow-chip-targets is the pure dim-vs-survivor split at the
    /// heart of this leaf: starting from jump-panes-chip-targets' own
    /// reshaped ((label . pane-id) …) list, a "aa"/"ad" two-key label
    /// survives under leader "a" (leader-prefix match, exactly the pairs
    /// jump-prefix-state minted this Visit's second-key edges from); a
    /// "bd" two-key label under a DIFFERENT leader and a bare single-key
    /// "e" label both dim, same as a non-panes kind ("ae"/workspaces) and
    /// an unassigned (#f) target both drop out entirely (jump-panes-chip-
    /// targets' own tail) — order is preserved within each group.
    @Test func jumpNarrowChipTargetsSplitsSurvivorsFromDimByLeader() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "aa" (list (cons 'kind 'panes) (cons 'id "w1:p1")))
                  (cons "ad" (list (cons 'kind 'panes) (cons 'id "w1:p2")))
                  (cons "bd" (list (cons 'kind 'panes) (cons 'id "w1:p3")))
                  (cons "e"  (list (cons 'kind 'panes) (cons 'id "w1:p4")))
                  (cons "ae" (list (cons 'kind 'workspaces) (cons 'id "w_9")))
                  (cons #f   (list (cons 'kind 'panes) (cons 'id "w1:p5")))))
          (define R (jump-narrow-chip-targets ASSIGNED "a"))
        """#)
        #expect(try engine.evaluate(
            "(equal? (cdr (assoc 'survivors R)) (list (cons \"aa\" \"w1:p1\") (cons \"ad\" \"w1:p2\")))") == .true)
        #expect(try engine.evaluate(
            "(equal? (cdr (assoc 'dim R)) (list (cons \"bd\" \"w1:p3\") (cons \"e\" \"w1:p4\")))") == .true)
    }

    /// A leader with no survivors at all (every panes chip dims) is a
    /// legitimate shape — not an error — e.g. between the leader keypress
    /// firing the provider re-mint and the FSM settling, or a future caller
    /// probing a leader no live target currently uses.
    @Test func jumpNarrowChipTargetsEmptySurvivorsWhenLeaderUnused() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "bd" (list (cons 'kind 'panes) (cons 'id "w1:p1")))
                  (cons "e"  (list (cons 'kind 'panes) (cons 'id "w1:p2")))))
          (define R (jump-narrow-chip-targets ASSIGNED "a"))
        """#)
        #expect(try engine.evaluate("(null? (cdr (assoc 'survivors R)))") == .true)
        #expect(try engine.evaluate("(= (length (cdr (assoc 'dim R))) 2)") == .true)
    }

    /// jump-narrow-chip-targets-of-kind generalises jump-narrow-chip-targets
    /// by KIND (mini-chip-painting-k32): the SAME leader-prefix survivor/dim
    /// split applies unchanged once jump-targets-of-kind has already
    /// filtered to one kind — proved here against 'tabs; jump-narrow-chip-
    /// targets (tested above) is this function's 'panes specialisation and
    /// is unchanged.
    @Test func jumpNarrowChipTargetsOfKindSplitsSurvivorsFromDimByLeader() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "aa" (list (cons 'kind 'tabs) (cons 'id "w1:t1")))
                  (cons "ad" (list (cons 'kind 'tabs) (cons 'id "w1:t2")))
                  (cons "bd" (list (cons 'kind 'tabs) (cons 'id "w1:t3")))
                  (cons "e"  (list (cons 'kind 'tabs) (cons 'id "w1:t4")))
                  (cons "ae" (list (cons 'kind 'panes) (cons 'id "w1:p9")))
                  (cons #f   (list (cons 'kind 'tabs) (cons 'id "w1:t5")))))
          (define R (jump-narrow-chip-targets-of-kind 'tabs ASSIGNED "a"))
        """#)
        #expect(try engine.evaluate(
            "(equal? (cdr (assoc 'survivors R)) (list (cons \"aa\" \"w1:t1\") (cons \"ad\" \"w1:t2\")))") == .true)
        #expect(try engine.evaluate(
            "(equal? (cdr (assoc 'dim R)) (list (cons \"bd\" \"w1:t3\") (cons \"e\" \"w1:t4\")))") == .true)
    }

    /// The narrowing prefix state must carry a live 'on-enter/'on-leave
    /// pair in its PAYLOAD (defer-chips-to-overlay-k33; `context` wires the
    /// SAME pair onto the root screen) — presentation-gated slots, so chips
    /// appear with the overlay rather than ahead of it. The payload is the
    /// alist fsm.sld's run-on-enter/run-on-leave read through
    /// node-on-enter/node-on-leave, and a narrowing descent lands with the
    /// overlay already open, so the repaint is still synchronous — the
    /// chips cleared by the root's own 'on-leave (fired by
    /// fire-group-descent! when descending INTO the prefix state) are
    /// repainted in the same call, upholding docs/specs/herdr-jump-
    /// navigation.md "Narrowing" ("ALL chips remain visible"). 'on-leave is
    /// literally clear-jump-chips! (hints-hide clears every group, narrowed
    /// or not); 'on-enter is a LEADER-closing lambda around
    /// paint-jump-chips-narrowed! (narrowing-dim-state-k30), not the bare
    /// paint-jump-chips! the root itself uses — it needs to know which
    /// leader this Visit narrowed into (see
    /// jumpNarrowChipTargetsSplitsSurvivorsFromDimByLeader for the
    /// leader-split logic itself). The state's own 'entry/'exit slots must
    /// stay unset — the double-fire trap: an 'entry alongside the payload's
    /// 'on-enter would paint the chips twice. 24 tab-scoped
    /// panes (mirroring herdrJumpProviderTwoKeyLabelNarrows... above)
    /// force leader "h" to escalate to two-key duty, minting a real
    /// prefix state to inspect. Calling herdr-jump-provider directly (not
    /// through activation/modal-handle-key) keeps this fixture-only;
    /// structural only — never invokes the hooks, so no AX/hints-show
    /// dependency.
    @Test func jumpPrefixStateWiresChipPaintOnEnterOnLeave() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser json) (modaliser util))")
        let paneEntries = (1...24).map { "{\"pane_id\":\"w1:p\($0)\",\"tab_id\":\"w1:t1\"}" }.joined(separator: ",")
        let paneListEscaped = "{\"result\":{\"panes\":[\(paneEntries)]}}"
            .replacingOccurrences(of: "\"", with: "\\\"")
        try engine.evaluate(#"""
          (define RESULT
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (cond
                     ((string=? method "pane.current")
                      (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                     ((string=? method "pane.list")
                      (json-parse "\#(paneListEscaped)"))
                     (else #f)))))
              (herdr-jump-provider)))
          (define STATES (cdr (assoc 'states RESULT)))
          (define PREFIX
            (find (lambda (s) (equal? (cdr (assoc 'id s)) "herdr/h")) STATES))
          (define PAYLOAD (cdr (assoc 'payload PREFIX)))
        """#)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-enter PAYLOAD)))") == .true)
        #expect(try engine.evaluate("(not (eq? (cdr (assoc 'on-enter PAYLOAD)) paint-jump-chips!))") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'on-leave PAYLOAD)) clear-jump-chips!)") == .true)
        #expect(try engine.evaluate("(not (cdr (assoc 'entry PREFIX)))") == .true)
        #expect(try engine.evaluate("(not (cdr (assoc 'exit PREFIX)))") == .true)
    }

    /// The behavioural half of the wiring check above
    /// (defer-chips-to-overlay-k33): chips paint WITH the overlay, never
    /// ahead of it. Driven through the real activation path, with the
    /// overlay's host hooks stubbed so `show-overlay` is what flips
    /// `overlay-open?` — exactly the ordering ui/overlay.scm establishes.
    ///
    /// `pane.layout` is the marker: herdr-paint-chip-targets!
    /// (blocks/herdr-list.sld) is the ONLY caller of that method in the
    /// whole tree, and it issues the query unconditionally, before any
    /// geometry or emptiness check — so its presence in the recorded
    /// method list means chips painted, and its absence means they did
    /// not. The query runner answers #f for it, yielding no canvas, which
    /// is also what keeps the AX host-frame lookup out of this test
    /// (herdr-jump-tests-live-ax-k50); current-herdr-host-frame is stubbed
    /// belt-and-braces on top.
    ///
    /// Two activations, one graph:
    ///   * a non-zero `modal-overlay-delay` — the delayed show is merely
    ///     SCHEDULED, so run-on-enter has not fired and nothing painted.
    ///     This is the fast muscle-memory press the leaf is about.
    ///   * a zero delay — modal-show-overlay-delayed's immediate branch
    ///     runs run-on-enter synchronously, and the chips paint.
    /// The intervening modal-exit also proves the pairing guarantee: a
    /// never-fired paint leaves nothing stranded, because run-on-leave is
    /// gated on the same overlay-open? that would have let run-on-enter
    /// fire (no clear runs, and none is needed).
    @Test func chipPaintWaitsForTheOverlayToShow() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes herdr) (modaliser json)
                  (only (modaliser blocks herdr-list) current-herdr-host-frame)
                  (modaliser muxes herdr-socket))
        """)
        try engine.evaluate(Self.herdrScreenFixture)
        try engine.evaluate("""
          (define methods '())
          (set-overlay-open! #f)
          (set-show-overlay! (lambda (root path) (set-overlay-open! #t)))
          (set-hide-overlay! (lambda () (set-overlay-open! #f)))
        """)
        // Both activations share this stub: the provider gets its canned
        // pane data (so real jump labels are assigned), every other method
        // — `pane.layout` included — answers #f.
        func activate(delay: String) throws {
            try engine.evaluate(#"""
              (set! methods '())
              (set-overlay-delay! \#(delay))
              (parameterize
                ((current-herdr-host-frame (lambda (total-w total-h) #f))
                 (current-herdr-query-runner
                   (lambda (method params)
                     (set! methods (cons method methods))
                     (cond
                       ((string=? method "pane.current")
                        (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                       ((string=? method "pane.list")
                        (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\"},{\"pane_id\":\"w1:p2\",\"tab_id\":\"w1:t1\"}]}}"))
                       (else #f)))))
                (modal-activate! "herdr" '() F18))
            """#)
        }

        // Fast press: the overlay show is only scheduled, so nothing paints.
        try activate(delay: "30")
        #expect(try engine.evaluate("(overlay-open?)") == .false)
        #expect(try engine.evaluate("(member \"pane.layout\" methods)") == .false)
        // The provider still ran — dispatch is never gated on presentation.
        #expect(try engine.evaluate("(and (member \"pane.list\" methods) #t)") == .true)

        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)

        // Overlay shows (delay 0 ⇒ synchronously): chips paint.
        try activate(delay: "0")
        #expect(try engine.evaluate("(overlay-open?)") == .true)
        #expect(try engine.evaluate("(and (member \"pane.layout\" methods) #t)") == .true)
    }

    // MARK: - Jump legend (leaf legend-panel-k44)

    /// Test seam 5 (docs/specs/herdr-jump-navigation.md "Test seams"):
    /// herdr-jump-legend-rows takes the snapshotted ASSIGNED list plus
    /// three canned `<x> list` envelopes and builds legend rows in the
    /// SAME gather order (spaces -> agents -> tabs -> panes) ASSIGNED is
    /// already in — label, joined name, kind. Agents and panes both read
    /// pane_id-keyed names off the SAME (unscoped) `pane list` envelope
    /// (row-title's "agent" field convention) — the agent's pane_id here
    /// ("w1:p9") is deliberately absent from any tab, proving name lookup
    /// doesn't depend on tab-scoping.
    @Test func herdrJumpLegendRowsBuildsRowsForEveryKindInGatherOrder() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-jump-legend) (modaliser json))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons "q" (list (cons 'kind 'workspaces) (cons 'id "w_1")))
                  (cons "h" (list (cons 'kind 'agents)     (cons 'id "w1:p9")))
                  (cons "j" (list (cons 'kind 'tabs)       (cons 'id "w1:t1")))
                  (cons "a" (list (cons 'kind 'panes)      (cons 'id "w1:p1")))))
          (define WORKSPACES (json-parse "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w_1\",\"label\":\"Alpha\"}]}}"))
          (define TABS (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w1:t1\",\"label\":\"Editor\"}]}}"))
          (define PANES (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"agent\":\"claude\"},{\"pane_id\":\"w1:p9\",\"agent\":\"gpt\"}]}}"))
          (define ROWS (herdr-jump-legend-rows ASSIGNED WORKSPACES TABS PANES))
        """#)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(4))
        #expect(try engine.evaluate("(cdr (assoc 'label (list-ref ROWS 0)))") == .string("q"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 0)))") == .string("Alpha"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (list-ref ROWS 0)))") == .string("Space"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 1)))") == .string("gpt"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (list-ref ROWS 1)))") == .string("Agent"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 2)))") == .string("Editor"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (list-ref ROWS 2)))") == .string("Tab"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 3)))") == .string("claude"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (list-ref ROWS 3)))") == .string("Pane"))
    }

    /// An unlabelled (#f) target — past a pool's exhaustion, jump-
    /// provider-result's own tail — is dropped: the legend can never show
    /// a row with no live chip behind it. A target whose id has no match
    /// in the name JSON (a gap, or #f envelopes when herdr degrades)
    /// falls back to the raw id rather than dropping the row
    /// (docs/specs/herdr-jump-navigation.md "Legend": "missing name ->
    /// raw id").
    @Test func herdrJumpLegendRowsDropsUnlabelledAndFallsBackToRawId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks herdr-jump-legend) (modaliser json))")
        try engine.evaluate(#"""
          (define ASSIGNED
            (list (cons #f  (list (cons 'kind 'workspaces) (cons 'id "w_2")))
                  (cons "a" (list (cons 'kind 'panes) (cons 'id "w1:p1")))))
          (define ROWS (herdr-jump-legend-rows ASSIGNED #f #f #f))
        """#)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'label (car ROWS)))") == .string("a"))
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS)))") == .string("w1:p1"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (car ROWS)))") == .string("Pane"))
    }

    /// jump-legend-block's block-spec carries no cursor-targets-fn / no
    /// block-children digit range — the legend is display-only, its jump
    /// label is never itself a dispatch key (dispatch lives in the FSM
    /// provider edges). The block's on-render-fn queries `workspace list`/
    /// `tab.list`/`pane.list` through current-herdr-query-runner (the SAME
    /// test seam the live-list blocks use, feedback_no_live_env_mutation_
    /// in_tests) — stubbed here to #f envelopes, which herdr-jump-legend-
    /// rows degrades gracefully; an empty *current-jump-assigned* (no
    /// activation in this test) yields an empty legend.
    @Test func jumpLegendBlockIsNonInteractiveAndRendersEmptyWithNoAssignment() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser blocks herdr-list))")
        try engine.evaluate("(define B (jump-legend-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type B)) 'herdr-jump-legend)") == .true)
        #expect(try engine.evaluate("(assoc 'cursor-targets-fn B)") == .false)
        #expect(try engine.evaluate("(assoc 'block-children B)") == .false)
        try engine.evaluate("""
          (define RENDERED
            (parameterize ((current-herdr-query-runner (lambda (method params) #f)))
              ((cdr (assoc 'on-render-fn B)))))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'rows RENDERED)))") == .true)
    }

    // MARK: - Narrowed jump legend (leaf narrowed-legend-k45)

    /// The narrowed variant reuses herdr-jump-legend-rows unchanged
    /// (blocks/herdr-jump-legend.sld): narrowed-jump-legend-block's
    /// 'assigned-fn returns the PREFIX state's own (second-char . target)
    /// survivor PAIRS directly — already the (label . target) shape the
    /// rows extractor takes, its "label" here being the remaining second
    /// key rather than a full jump label. No new rows extractor, no
    /// re-query: names still come from current-herdr-query-runner (the
    /// SAME seam jump-legend-block uses), fixture-tested here with no
    /// live herdr.
    @Test func narrowedJumpLegendBlockRendersSurvivorRowsFromGivenPairs() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser blocks herdr-list) (modaliser json))")
        try engine.evaluate(#"""
          (define PAIRS
            (list (cons "a" (list (cons 'kind 'panes) (cons 'id "w1:p5")))
                  (cons "d" (list (cons 'kind 'panes) (cons 'id "w1:p6")))))
          (define B (narrowed-jump-legend-block PAIRS))
        """#)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type B)) 'herdr-jump-legend)") == .true)
        #expect(try engine.evaluate("(assoc 'cursor-targets-fn B)") == .false)
        try engine.evaluate(#"""
          (define RENDERED
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (if (string=? method "pane.list")
                       (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p5\",\"agent\":\"claude\"},{\"pane_id\":\"w1:p6\",\"agent\":\"gpt\"}]}}")
                       #f))))
              ((cdr (assoc 'on-render-fn B)))))
          (define ROWS (cdr (assoc 'rows RENDERED)))
        """#)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(2))
        #expect(try engine.evaluate("(cdr (assoc 'label (list-ref ROWS 0)))") == .string("a"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 0)))") == .string("claude"))
        #expect(try engine.evaluate("(cdr (assoc 'detail (list-ref ROWS 0)))") == .string("Pane"))
        #expect(try engine.evaluate("(cdr (assoc 'label (list-ref ROWS 1)))") == .string("d"))
        #expect(try engine.evaluate("(cdr (assoc 'title (list-ref ROWS 1)))") == .string("gpt"))
    }

    /// The prefix state's payload carries the two-layer node shape — the
    /// legend block as a flat dispatch child plus one 'display panel clause
    /// referencing it by id (narrowed-legend-k45, readers-cutover) — the
    /// SAME shape `screen` lowers a registered root's payload into, so
    /// ui/overlay.scm's UNCHANGED panel-grid renderer draws this
    /// survivor legend: fsm-resolved-payload (fsm.sld) hands the provided
    /// state's payload straight through as modal-current-node, "so a
    /// provided RESTING state ... must present the same way a permanent
    /// one does" (its own doc comment) — no fsm.sld/state-machine.sld/
    /// overlay.scm change needed, only this payload shape. 6 tab-scoped
    /// panes exceed the panes pool's 5 single-key slots by exactly one,
    /// so jump-labels-assign's escalation (jump-labels.sld's
    /// compute-escalation) promotes ONLY leader "h" (its own pool's first
    /// letter) to two-key duty — p1..p4 keep the remaining singles
    /// "j" "k" "l" ";", p5/p6 escalate to "ha"/"hs" — minting a real
    /// prefix state with EXACTLY two survivors (p5, p6) to inspect. A
    /// larger pane count (e.g. 24, as
    /// herdrJumpProviderTwoKeyLabelNarrowsThenFiresAndBackspaceUnNarrows
    /// above uses) still promotes only leader "h" but escalates every
    /// pane past p4 under it, so this test deliberately stays small
    /// enough that leader "a"'s survivor set is small and exhaustively
    /// checkable. Structural only: never invokes entry/exit, no
    /// AX/hints-show dependency; the panel's embedded block's
    /// on-render-fn IS invoked (parameterized) to prove the survivor rows
    /// are exactly p5/p6, in second-key order, reading names through
    /// current-herdr-query-runner.
    @Test func jumpPrefixStatePayloadCarriesNarrowedLegendPanel() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser muxes herdr) (modaliser blocks herdr-list)
                  (modaliser fsm) (modaliser json) (modaliser util))
        """)
        let paneEntries = (1...6).map { "{\"pane_id\":\"w1:p\($0)\",\"tab_id\":\"w1:t1\"}" }.joined(separator: ",")
        let paneListEscaped = "{\"result\":{\"panes\":[\(paneEntries)]}}"
            .replacingOccurrences(of: "\"", with: "\\\"")
        try engine.evaluate(#"""
          (define RESULT
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (cond
                     ((string=? method "pane.current")
                      (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w1:p1\",\"tab_id\":\"w1:t1\",\"workspace_id\":\"w1\"}}}"))
                     ((string=? method "pane.list")
                      (json-parse "\#(paneListEscaped)"))
                     (else #f)))))
              (herdr-jump-provider)))
          (define STATES (cdr (assoc 'states RESULT)))
          (define PREFIX
            (find (lambda (s) (equal? (cdr (assoc 'id s)) "herdr/h")) STATES))
          (define PAYLOAD (cdr (assoc 'payload PREFIX)))
          (define CHILDREN (node-children PAYLOAD))
          ;; Two-layer payload shape (ADR-0011): the legend block is the
          ;; one flat dispatch child; the display value's panel clause
          ;; places it by reference.
          (define BLOCK (car CHILDREN))
          (define JUMP-PANEL (car (node-display-ref PAYLOAD 'panels)))
        """#)
        #expect(try engine.evaluate("(length CHILDREN)") == .fixnum(1))
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type BLOCK)) 'herdr-jump-legend)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label JUMP-PANEL)) \"Jump\")") == .true)
        #expect(try engine.evaluate(
            "(equal? (cdr (assoc 'rows JUMP-PANEL)) '((block . herdr-jump-legend)))") == .true)
        try engine.evaluate(#"""
          (define RENDERED
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (if (string=? method "pane.list")
                       (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p5\",\"agent\":\"claude\"},{\"pane_id\":\"w1:p6\",\"agent\":\"gpt\"}]}}")
                       #f))))
              ((cdr (assoc 'on-render-fn BLOCK)))))
          (define ROWS (cdr (assoc 'rows RENDERED)))
        """#)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(2))
        #expect(try engine.evaluate(
            "(equal? (map (lambda (r) (cdr (assoc 'label r))) ROWS) (list \"a\" \"s\"))") == .true)
        #expect(try engine.evaluate(
            "(equal? (map (lambda (r) (cdr (assoc 'title r))) ROWS) (list \"claude\" \"gpt\"))") == .true)
    }

    // MARK: - Reachability (herdr's replacement for ADR-0017 Layer 2)

    /// End-to-end: an unresponsive herdr makes the affected block
    /// (blocks/herdr-list.sld) render a message row instead of an empty
    /// list, and recovery — herdr answering again mid-run, no relaunch —
    /// restores real rows on the very next render.
    ///
    /// The signal is the QUERY RESULT itself, with no health table behind
    /// it (list-block-query-cutover-k32): over the socket a #f means herdr
    /// did not answer, full stop, and a reachable herdr with nothing to
    /// list answers a truthy `{"result":{"panes":[]}}` instead. That is
    /// what the shell-out era could not distinguish — `2>/dev/null` gave
    /// the same empty string either way — and why herdr needed ADR-0017's
    /// `command -v` re-probe to recover the difference.
    @Test func herdrListRendersUnresponsiveMessageAndRecoversWithoutRelaunch() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (modaliser muxes herdr) (modaliser muxes herdr-socket)
                  (modaliser blocks herdr-list)
                  (modaliser terminal) (modaliser json))
        """)
        try engine.evaluate("(define B (make-herdr-list-block 'kind 'panes))")
        try engine.evaluate(#"""
          (define RENDERED
            (parameterize ((current-herdr-query-runner (lambda (method params) #f)))
              ((cdr (assoc 'on-render-fn B)))))
          (define ROWS (cdr (assoc 'rows RENDERED)))
        """#)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'label (car ROWS)))") == .string(""))
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS)))")
                == .string("herdr is not responding"))
        #expect(try engine.evaluate("(null? (herdr-list-current-targets))") == .true)

        // herdr answers again mid-run; the next render's own query is all
        // it takes to restore real rows.
        try engine.evaluate(#"""
          (define RENDERED2
            (parameterize
              ((current-herdr-query-runner
                 (lambda (method params)
                   (json-parse "{\"result\":{\"panes\":[{\"pane_id\":\"w1:p1\",\"agent\":\"claude\",\"focused\":true,\"tab_id\":\"w1:t1\"}]}}"))))
              ((cdr (assoc 'on-render-fn B)))))
          (define ROWS2 (cdr (assoc 'rows RENDERED2)))
        """#)
        #expect(try engine.evaluate("(length ROWS2)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'title (car ROWS2)))") == .string("claude"))
        #expect(try engine.evaluate("(length (herdr-list-current-targets))") == .fixnum(1))
    }

    /// A reachable herdr with genuinely nothing to list is NOT the
    /// unresponsive case: the envelope parses truthy and flows into the
    /// pure extractor as zero rows. This is the distinction the socket
    /// buys and the shell-out could not make, so it is pinned.
    @Test func reachableHerdrWithAnEmptyListIsNotTheUnresponsiveCase() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr-socket) (modaliser blocks herdr-list)
                  (modaliser json))
        """)
        try engine.evaluate("(define B (make-herdr-list-block 'kind 'panes))")
        try engine.evaluate(#"""
          (define ROWS
            (cdr (assoc 'rows
              (parameterize
                ((current-herdr-query-runner
                   (lambda (method params) (json-parse "{\"result\":{\"panes\":[]}}"))))
                ((cdr (assoc 'on-render-fn B)))))))
        """#)
        #expect(try engine.evaluate("(null? ROWS)") == .true)
        #expect(try engine.evaluate("(null? (herdr-list-current-targets))") == .true)
    }

    /// herdr has LEFT ADR-0017 Layer 2: its backend record carries no
    /// tool-name, so installing it fires no `command -v` probe at all —
    /// not at backend install, and not lazily on a failed query. The
    /// backend that reaches herdr over a socket must never look a binary
    /// up on the tool path (ADR-0020's whole point is de-subprocessing
    /// this path). Layer 2 itself is untouched and still covers the
    /// CLI-native backends — see ModaliserTerminalLibraryTests.
    @Test func herdrBackendCarriesNoToolNameAndNeverProbesTheToolPath() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser fsm)
                  (modaliser muxes herdr) (modaliser muxes herdr-socket)
                  (modaliser blocks herdr-list)
                  (modaliser terminal) (modaliser json))
        """)
        try engine.evaluate("""
          (define probe-count 0)
          (parameterize ((current-tool-probe-runner
                           (lambda (tool) (set! probe-count (+ probe-count 1)) #t)))
            (terminal-install-backends! (list backend)))
          """)
        #expect(try engine.evaluate("probe-count") == .fixnum(0))

        // Nor on the failing-query path that used to be the ambiguous
        // moment: a #f is now the verdict, not a trigger to go looking for
        // a binary (feedback_no_live_env_mutation_in_tests — an escaped
        // probe would run the REAL `command -v herdr`).
        try engine.evaluate("(define B (make-herdr-list-block 'kind 'panes))")
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-query-runner (lambda (method params) #f))
             (current-tool-probe-runner
               (lambda (tool) (set! probe-count (+ probe-count 1)) #t)))
            ((cdr (assoc 'on-render-fn B))))
        """#)
        #expect(try engine.evaluate("probe-count") == .fixnum(0))
        #expect(try engine.evaluate("(backend-tool-missing? 'herdr)") == .false)
    }
}
