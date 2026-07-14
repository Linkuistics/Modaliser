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
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        // The only public exports are register! and backend; the ops
        // live on the façade, not here. Both must bind without error.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend into the façade's registry, keyed
    /// by 'herdr + match-key "herdr". With a stubbed host reporting
    /// "herdr" as its foreground command, the façade walks the path and
    /// the leaf is this backend — the detection premise validated live
    /// against the herdr-in-iTerm client (an iTerm pane running herdr
    /// reports tty foreground command "herdr").
    @Test func registerInstallsHerdrBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes herdr) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        // A stub host that claims herdr is in the focused pane. The path
        // walk descends from host into the herdr backend; without a live
        // herdr session the backend's detect-fg returns #f, so it sits at
        // the leaf naturally.
        try engine.evaluate("""
          (define stub-host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle"
              (lambda () "herdr")      ; foreground command → descend into herdr
              (lambda () "host-1")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! stub-host)
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

    /// (register!) also wires the digit-pick mode so that the backend's
    /// focus-pane-by-digit symbol ('herdr-pane-digit) names a real tree
    /// for the façade's resolver to hand a procedure-valued 'next.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes herdr))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"herdr-pane-digit\")") != .false)
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
        try engine.evaluate("(register-backend! backend)")
        try engine.evaluate("""
          (define h
            (make-terminal-backend
              'sh "H" 'host "t.b"
              (lambda () "herdr") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! h)
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
        try engine.evaluate("(register!)")
        // A host reporting some *other* fg command must NOT resolve herdr.
        try engine.evaluate("""
          (define other-host
            (make-terminal-backend
              'other "Other" 'host "other.bundle"
              (lambda () "bash") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! other-host)
        """)
        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "other.bundle")))
            (in-chain? 'herdr))
        """)
        #expect(inChain == .false)
    }

    // MARK: - herdr-in-iTerm variant wiring (leaf 3, ADR-0013)

    /// The replace/augment classifier (R1). Keyed on the CURRENT-TAB iTerm
    /// split count: the sole split → replace ("/herdr"); any others →
    /// augment ("/herdr+split"). A 0 count (an AppleScript hiccup while
    /// herdr is confirmed focused) degrades to replace — the safe default.
    @Test func classifierMapsCurrentTabSplitCount() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        func suffix(_ n: Int) throws -> String {
            let v = try engine.evaluate("(classify-herdr-variant \(n))")
            if case .string(let s) = v { return s as String }
            Issue.record("expected string, got \(v)")
            return ""
        }
        #expect(try suffix(1) == "/herdr")           // sole split → replace
        #expect(try suffix(2) == "/herdr+split")     // + other splits → augment
        #expect(try suffix(5) == "/herdr+split")
        #expect(try suffix(0) == "/herdr")           // defensive → replace
    }

    /// The tree-builders are shape-correct and the iTerm exports the config
    /// composes with are reachable. `iterm-list-session-ids` is the
    /// tab-scoped classifier count source (`sessions of current tab of
    /// current window`) — the fix for the multi-tab trap (R1) — asserted
    /// exported but NOT called (it would auto-launch iTerm via AppleScript;
    /// the config wires it as the count source, gated on herdr being
    /// focused, i.e. iTerm already frontmost). `build-iterm-splits-drill` is
    /// pure (builds a node), so it is exercised here.
    @Test func treeBuildersAndItermExportsAreShapeCorrect() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr)
                  (only (modaliser apps iterm)
                        iterm-list-session-ids build-iterm-splits-drill))
        """)
        #expect(try engine.evaluate("(procedure? iterm-list-session-ids)") == .true)
        // Skeleton herdr tree: a non-empty list of nodes (herdr owns hjkl).
        #expect(try engine.evaluate("(pair? (build-herdr-tree))") == .true)
        // The augment iTerm-splits drill builds a node (pure, no AppleScript).
        #expect(try engine.evaluate("(pair? (build-iterm-splits-drill))") == .true)
    }

    /// R4 — the context-suffix variant path of `resolve-app-tree` was
    /// implemented but NEVER exercised in production (no /nvim or /zellij
    /// screen ships in the bundled config); herdr is its first real user.
    /// This asserts the variant actually RESOLVES rather than silently
    /// falling back to the plain tree. Registers the base + both variant
    /// screens + the herdr backend + a stub iTerm host whose focused pane
    /// runs herdr, installs the composed suffix hook (current-tab count
    /// injected so no live iTerm is touched), and checks all three outcomes.
    @Test func variantTreeResolvesReplaceAugmentAndFallback() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes herdr) (modaliser terminal)
                  (only (modaliser event-dispatch)
                        set-local-context-suffix! resolve-app-tree))
        """)
        // Base tree + both variant screens (skeletons).
        try engine.evaluate("""
          (screen 'com.googlecode.iterm2 (panel "Base" (key "x" "X" (lambda () #f))))
          (apply screen 'com.googlecode.iterm2/herdr (build-herdr-tree))
          (apply screen 'com.googlecode.iterm2/herdr+split (build-herdr-tree))
        """)
        // herdr backend + a stub iTerm host whose focused pane runs herdr.
        try engine.evaluate("(register!)")
        try engine.evaluate("""
          (define (stub-iterm fg)
            (make-terminal-backend
              'iterm "iTerm" 'host "com.googlecode.iterm2"
              (lambda () fg) (lambda () "sess-1")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! (stub-iterm "herdr"))
        """)
        // Composed hook: herdr focused → classify by the injected current-tab
        // split count; otherwise #f (fall back to the plain tree).
        try engine.evaluate("""
          (define *ct-count* 1)
          (set-local-context-suffix!
            (lambda (bundle-id)
              (and (equal? bundle-id "com.googlecode.iterm2")
                   (in-chain? 'herdr)
                   (classify-herdr-variant *ct-count*))))
        """)
        func resolvesTo(_ variant: String) throws -> Bool {
            try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "com.googlecode.iterm2")))
                (eq? (resolve-app-tree "com.googlecode.iterm2")
                     (lookup-tree "\(variant)")))
            """) == .true
        }
        // Replace: sole current-tab split → the /herdr variant resolves.
        #expect(try resolvesTo("com.googlecode.iterm2/herdr"))
        // Augment: >1 current-tab split → the /herdr+split variant resolves.
        try engine.evaluate("(set! *ct-count* 2)")
        #expect(try resolvesTo("com.googlecode.iterm2/herdr+split"))
        // Fall-through: herdr NOT focused → the plain tree, no variant.
        try engine.evaluate("(register-backend! (stub-iterm \"zsh\"))")
        #expect(try resolvesTo("com.googlecode.iterm2"))
    }

    // MARK: - herdr control surface (leaf herdr-controls-k9)

    /// `build-herdr-tree` returns the full herdr surface, not the hjkl
    /// skeleton: a `p` Panes drill (Focus panel, n New / m Move groups, z/d
    /// pane keys, the Panes list panel), the t Tabs / w Workspaces /
    /// g Worktrees drills, the b Jump-to-Blocked key, a Agents drill (agents
    /// surface, k13), and the q Quit group (herdr-quit-group-k2) — seven
    /// top-level nodes (herdr-pane-group grove). It must build without
    /// touching herdr (all shell-outs live in
    /// on-render thunks / key actions, never at construction time).
    @Test func buildHerdrTreeIsFullSurface() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        #expect(try engine.evaluate("(length (build-herdr-tree))") == .fixnum(7))
    }

    /// (register!) wires the Walk top-level focus mode the herdr tree's
    /// Focus panel crosses into ('next 'herdr-panes-focus), so a
    /// first hjkl focuses AND keeps moving without another leader press.
    @Test func registerInstallsWalkFocusMode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"herdr-panes-focus\")") != .false)
    }

    /// ADR-0015 live smoke: dispatching through the REAL build-herdr-tree's
    /// `p` Panes drill, "m" Move group. Each hjkl carries 'next 'self (a
    /// cyclic edge), so repeat presses re-arm in place — no exit, no
    /// modal-stack growth — and an unrelated key still exits per
    /// 'exit-on-unknown.
    @Test func movePaneWalkReArmsInPlaceAndExitsOnUnknownKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("""
          (apply screen 'com.googlecode.iterm2/herdr (build-herdr-tree))
        """)
        try engine.evaluate("(modal-enter (lookup-tree \"com.googlecode.iterm2/herdr\") F18)")
        try engine.evaluate("(modal-handle-key \"p\")")
        try engine.evaluate("(modal-handle-key \"m\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"p\" \"m\"))") == .true)

        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"p\" \"m\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-handle-key \"q\")") // unbound in Move
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    /// ADR-0015 live smoke: the `p` Panes drill's Focus panel's hjkl carry
    /// 'next 'herdr-panes-focus (a cross edge) — the first press pushes the
    /// caller (the herdr tree, inside the Panes drill) and switches into
    /// the Walk; subsequent hjkl inside it cycle via 'next 'self with no
    /// further push; backspace pops back to the caller.
    @Test func focusPanelCrossesIntoWalkThenCyclesInPlace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("(register!)") // registers 'herdr-panes-focus
        try engine.evaluate("""
          (apply screen 'com.googlecode.iterm2/herdr (build-herdr-tree))
        """)
        try engine.evaluate("(modal-enter (lookup-tree \"com.googlecode.iterm2/herdr\") F18)")
        try engine.evaluate("(modal-handle-key \"p\")") // Panes drill
        try engine.evaluate("(modal-handle-key \"h\")") // Focus panel
        #expect(try engine.evaluate(
            "(eq? modal-root-node (lookup-tree \"herdr-panes-focus\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-handle-key \"j\")")
        try engine.evaluate("(modal-handle-key \"k\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate(
            "(eq? modal-root-node (lookup-tree \"com.googlecode.iterm2/herdr\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    /// herdr-fast-key-drops-k8: reproduces the reported "leader, w, <digit>
    /// typed fast doesn't work" bug and proves the fix.
    ///
    /// current-targets / current-kind is ONE cell shared by every herdr-list
    /// kind (the single-render invariant, blocks/herdr-list.sld). A group
    /// descent only renders synchronously when the overlay is already open
    /// (modal-handle-key's group? branch, state-machine.sld) — never true in
    /// this hermetic harness, which installs no overlay backend, exactly
    /// mirroring a real press faster than modal-overlay-delay. So pressing
    /// "w" then a digit here reaches the digit key-range without Workspaces
    /// ever having snapshotted.
    ///
    /// Simulates a Panes render earlier in the session (current-kind =
    /// 'panes, label "1" → a pane id), then presses "w" "1" with no
    /// Workspaces render in between: the digit must not accept the stale
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
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr)
                  (modaliser blocks herdr-list) (modaliser json))
        """)
        try engine.evaluate("""
          (apply screen 'com.googlecode.iterm2/herdr (build-herdr-tree))
        """)

        // Prior render this session: Panes, label "1" → a stale pane id.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-list-runner
               (lambda (subcmd)
                 (cond
                   ((string=? subcmd "pane list")
                    (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"focused\":true,\"pane_id\":\"STALE-PANE\",\"tab_id\":\"w1:t1\"}]}}"))
                   (else #f)))))
            (herdr-list-refresh! 'panes #f))
        """#)
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'panes)") == .true)
        #expect(try engine.evaluate("(cdr (assoc \"1\" (herdr-list-current-targets)))")
                == .string("STALE-PANE"))

        // Fast leader→w→1: the overlay never opens in this harness, so "w"'s
        // descent does not render Workspaces before "1" fires.
        try engine.evaluate("(modal-enter (lookup-tree \"com.googlecode.iterm2/herdr\") F18)")
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-list-runner
               (lambda (subcmd)
                 (cond
                   ((string=? subcmd "workspace list")
                    (json-parse "{\"result\":{\"workspaces\":[{\"focused\":true,\"label\":\"work\",\"workspace_id\":\"REAL-WORKSPACE\"}]}}"))
                   (else #f)))))
            (modal-handle-key "w")
            (modal-handle-key "1"))
        """#)

        // The digit forced a real Workspaces snapshot instead of trusting
        // the stale Panes entry under the same label.
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'workspaces)") == .true)
        #expect(try engine.evaluate("(cdr (assoc \"1\" (herdr-list-current-targets)))")
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

    /// The agents surface is wired into `build-herdr-tree`: a top-level `b`
    /// (Jump to Blocked, one keystroke) and an `a` Agents drill (open), both
    /// riding into the replace AND augment variant screens for free (the config
    /// already splices build-herdr-tree into both). Tree-shape assertion, no
    /// live herdr.
    @Test func buildHerdrTreeWiresJumpAndAgents() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("""
          (define TREE (build-herdr-tree))
          (define (node-key n) (let ((e (assoc 'key n))) (and e (cdr e))))
          (define (node-with-key k lst)
            (cond ((null? lst) #f)
                  ((equal? (node-key (car lst)) k) (car lst))
                  (else (node-with-key k (cdr lst)))))
        """)
        // Top-level `b` present and is a plain command key (Terminal jump, not a Walk).
        #expect(try engine.evaluate("(if (node-with-key \"b\" TREE) #t #f)") == .true)
        #expect(try engine.evaluate("""
          (eq? 'command (cdr (assoc 'kind (node-with-key "b" TREE))))
        """) == .true)
        // Top-level `a` present and is a drill group (the Agents open).
        #expect(try engine.evaluate("(if (node-with-key \"a\" TREE) #t #f)") == .true)
        #expect(try engine.evaluate("""
          (eq? 'group (cdr (assoc 'kind (node-with-key "a" TREE))))
        """) == .true)
    }

    // MARK: - Worktrees tree wiring (leaf worktrees-tree-wiring-k15)

    /// The pure smart-switch target parser (W4). k14 hands each worktree row a
    /// tagged switch target computed over the `worktree list` payload; this
    /// turns it back into a herdr command. An OPEN worktree ("ws:<id>") maps to
    /// the clean `workspace focus <id>`; a DORMANT one ("br:<branch>") maps to
    /// `worktree open --branch <branch> --focus`, source-pinned via --workspace
    /// when the focused ws-id is known and sq-escaped so an apostrophe in the
    /// branch is shell-safe. Malformed / empty / non-string targets → #f (never
    /// dispatched). Fixture-fed — no live herdr.
    @Test func worktreeSwitchCommandParsesTarget() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr))")
        // Open worktree → focus its live workspace (no --workspace pin needed).
        #expect(try engine.evaluate(#"(worktree-switch-command "ws:w12" "w9")"#)
                == .string("workspace focus w12"))
        // Dormant worktree → open a fresh workspace on the branch, source-pinned.
        #expect(try engine.evaluate(#"(worktree-switch-command "br:feature-x" "w9")"#)
                == .string("worktree open --workspace w9 --branch 'feature-x' --focus"))
        // No focused ws-id → degrade to herdr's implicit resolution (no pin).
        #expect(try engine.evaluate(#"(worktree-switch-command "br:feature-x" #f)"#)
                == .string("worktree open --branch 'feature-x' --focus"))
        // A branch with an apostrophe is sq-escaped ('\'' idiom) → shell-safe.
        #expect(try engine.evaluate(#"(worktree-switch-command "br:it's" "w9")"#)
                == .string(#"worktree open --workspace w9 --branch 'it'\''s' --focus"#))
        // Malformed tag, empty payload, and non-string all → #f (no dispatch).
        #expect(try engine.evaluate(#"(worktree-switch-command "xx:foo" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "ws:" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "br:" "w9")"#) == .false)
        #expect(try engine.evaluate(#"(worktree-switch-command "" "w9")"#) == .false)
        #expect(try engine.evaluate("(worktree-switch-command #f \"w9\")") == .false)
    }

    /// The worktrees surface is wired into `build-herdr-tree`: a top-level `g`
    /// Worktrees drill (open), riding into the replace AND augment variant
    /// screens for free (the config already splices build-herdr-tree into both).
    /// Its inner `n` New and `d` Remove keys are present. Tree-shape assertion,
    /// no live herdr.
    @Test func buildHerdrTreeWiresWorktrees() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("""
          (define TREE (build-herdr-tree))
          (define (node-key n) (let ((e (assoc 'key n))) (and e (cdr e))))
          (define (node-with-key k lst)
            (cond ((null? lst) #f)
                  ((equal? (node-key (car lst)) k) (car lst))
                  (else (node-with-key k (cdr lst)))))
        """)
        // Top-level `g` present and is a drill group (the Worktrees open).
        #expect(try engine.evaluate("(if (node-with-key \"g\" TREE) #t #f)") == .true)
        #expect(try engine.evaluate("""
          (eq? 'group (cdr (assoc 'kind (node-with-key "g" TREE))))
        """) == .true)
        // The drill holds `n` (New) and `d` (Remove) among its children.
        try engine.evaluate("""
          (define G (node-with-key "g" TREE))
          (define KIDS (cdr (assoc 'children G)))
        """)
        #expect(try engine.evaluate("(if (node-with-key \"n\" KIDS) #t #f)") == .true)
        #expect(try engine.evaluate("(if (node-with-key \"d\" KIDS) #t #f)") == .true)
    }

    // MARK: - Async herdr ops (leaf herdr-dialogs-async-k2)

    /// ADR-0014: worktree create/remove fire fire-and-forget async with no
    /// continuation payload — herdr's own UI, no missing-arg gap (unlike
    /// the rename ops below, moved off this bare-fire shape at
    /// herdr-rename-prompt-ownership-k9). Both the id-resolution query and
    /// the async fire are routed through parameterized test seams so no
    /// test spawns a real herdr (feedback_no_live_env_mutation_in_tests):
    /// current-herdr-query-runner hands back canned `pane current` JSON in
    /// place of a live query; current-herdr-async-runner captures the
    /// exact verb string in place of firing run-shell-async.
    @Test func worktreeOpsFireExactAsyncVerbsWithFocusedId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser json))")
        try engine.evaluate(#"""
          (define captured '())
          (parameterize
            ((current-herdr-query-runner
               (lambda (args)
                 (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}")))
             (current-herdr-async-runner
               (lambda (args callback) (set! captured (cons args captured)))))
            (new-worktree!)
            (remove-focused-worktree!))
          (set! captured (reverse captured))
        """#)
        #expect(try engine.evaluate("(list-ref captured 0)")
                == .string("worktree create --workspace w9 --focus"))
        #expect(try engine.evaluate("(list-ref captured 1)")
                == .string("worktree remove --workspace w9"))
    }

    /// herdr-rename-prompt-ownership-k9: the two rename ops no longer fire
    /// bare — they open a Modaliser-owned chooser-prompt (via the
    /// (modaliser state-machine) open-chooser-prompt deferred hook, the
    /// same shape open-chooser uses) pre-filled with the id's current
    /// label, read via `tab list` (the same query the live-list blocks
    /// already use). Only submitting the prompt's continuation fires the
    /// async verb, with the (possibly edited) label sq-escaped and
    /// single-quoted exactly like worktree-switch-command's branch-name
    /// interpolation. open-chooser-prompt is a plain setter (not a
    /// parameter), so it's stubbed directly rather than parameterized —
    /// the stub captures the (prompt, initial-value, on-submit) triple
    /// without a real WebView.
    @Test func renameFocusedTabOpensPromptPrefilledAndFiresEscapedLabelOnSubmit() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr) (modaliser state-machine) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define captured-prompt #f)
          (define captured-initial #f)
          (define captured-submit #f)
          (define captured-cmd #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit)
              (set! captured-prompt prompt)
              (set! captured-initial initial)
              (set! captured-submit on-submit)))
          (parameterize
            ((current-herdr-query-runner
               (lambda (args)
                 (cond
                   ((string=? args "pane current")
                    (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}"))
                   ((string=? args "tab list")
                    (json-parse "{\"result\":{\"tabs\":[{\"tab_id\":\"w9:t1\",\"label\":\"main\"}]}}"))
                   (else #f))))
             (current-herdr-async-runner
               (lambda (args callback) (set! captured-cmd args))))
            (rename-focused-tab!)
            (captured-submit "feature work"))
        """#)
        #expect(try engine.evaluate("captured-prompt").asString() == "Rename tab…")
        #expect(try engine.evaluate("captured-initial").asString() == "main")
        #expect(try engine.evaluate("captured-cmd").asString()
                == "tab rename w9:t1 'feature work'")
    }

    /// Same shape as the tab test above, plus the sq-escape case: an
    /// apostrophe in the submitted label must reach the fired verb via the
    /// close-quote/escaped-literal/reopen idiom (POSIX single-quote
    /// escaping), not break the shell-command quoting.
    @Test func renameFocusedWorkspaceOpensPromptPrefilledAndEscapesApostropheOnSubmit() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr) (modaliser state-machine) (modaliser json))
        """)
        try engine.evaluate(#"""
          (define captured-prompt #f)
          (define captured-initial #f)
          (define captured-submit #f)
          (define captured-cmd #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit)
              (set! captured-prompt prompt)
              (set! captured-initial initial)
              (set! captured-submit on-submit)))
          (parameterize
            ((current-herdr-query-runner
               (lambda (args)
                 (cond
                   ((string=? args "pane current")
                    (json-parse "{\"result\":{\"pane\":{\"pane_id\":\"w9:p1\",\"tab_id\":\"w9:t1\",\"workspace_id\":\"w9\"}}}"))
                   ((string=? args "workspace list")
                    (json-parse "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w9\",\"label\":\"work\"}]}}"))
                   (else #f))))
             (current-herdr-async-runner
               (lambda (args callback) (set! captured-cmd args))))
            (rename-focused-workspace!)
            (captured-submit "it's mine"))
        """#)
        #expect(try engine.evaluate("captured-prompt").asString() == "Rename workspace…")
        #expect(try engine.evaluate("captured-initial").asString() == "work")
        #expect(try engine.evaluate("captured-cmd").asString()
                == "workspace rename w9 'it'\\''s mine'")
    }

    /// The guard: with no focused id (herdr unreachable — `pane current`
    /// resolves to #f), all four ops no-op — neither the async runner nor
    /// (for the two rename ops) open-chooser-prompt is ever invoked. The
    /// query runner is explicitly stubbed to #f rather than relying on the
    /// ambient environment lacking herdr, so the assertion holds
    /// regardless of whether the host machine has a live herdr session.
    @Test func fourHerdrOpsNoOpWithoutFocusedId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes herdr) (modaliser state-machine) (modaliser json))
        """)
        try engine.evaluate("""
          (define fired? #f)
          (define prompted? #f)
          (set-open-chooser-prompt!
            (lambda (prompt initial on-submit) (set! prompted? #t)))
          (parameterize
            ((current-herdr-query-runner (lambda (args) #f))
             (current-herdr-async-runner (lambda (args callback) (set! fired? #t))))
            (rename-focused-tab!)
            (rename-focused-workspace!)
            (new-worktree!)
            (remove-focused-worktree!))
        """)
        #expect(try engine.evaluate("fired?") == .false)
        #expect(try engine.evaluate("prompted?") == .false)
    }

    // MARK: - Quit group (leaf herdr-quit-group-k2)

    /// Tree-shape only: top-level `q` is a group holding `d` Detach and `s`
    /// Stop Server. Detach's keystroke-emission body stays untested by
    /// design (same trust level as the config's untested copy-mode key) —
    /// no new keystroke test seam, per the grilled decision.
    @Test func buildHerdrTreeWiresQuitGroup() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("""
          (define TREE (build-herdr-tree))
          (define (node-key n) (let ((e (assoc 'key n))) (and e (cdr e))))
          (define (node-with-key k lst)
            (cond ((null? lst) #f)
                  ((equal? (node-key (car lst)) k) (car lst))
                  (else (node-with-key k (cdr lst)))))
        """)
        // Top-level `q` present and is a plain group (not a Walk/drill).
        #expect(try engine.evaluate("(if (node-with-key \"q\" TREE) #t #f)") == .true)
        #expect(try engine.evaluate("""
          (eq? 'group (cdr (assoc 'kind (node-with-key "q" TREE))))
        """) == .true)
        // Its children hold `d` (Detach) and `s` (Stop Server).
        try engine.evaluate("""
          (define Q (node-with-key "q" TREE))
          (define KIDS (cdr (assoc 'children Q)))
        """)
        #expect(try engine.evaluate("(if (node-with-key \"d\" KIDS) #t #f)") == .true)
        #expect(try engine.evaluate("(if (node-with-key \"s\" KIDS) #t #f)") == .true)
    }

    /// Stop Server behaviour (ADR-0014): cancel fires no async verb; OK
    /// fires exactly "server stop". Routed through the same
    /// current-dialog-runner + current-herdr-async-runner seams already
    /// used elsewhere in this file — no new test seam.
    @Test func stopServerFiresOnConfirmOnlyAndDoesNothingOnCancel() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes herdr) (modaliser dialogs))")

        // Cancel clicked (stdout doesn't match the "Stop" ok-label) → no fire.
        try engine.evaluate("""
          (define fired? #f)
          (parameterize
            ((current-dialog-runner (lambda (cmd cb) (cb 0 "Cancel\\n" "")))
             (current-herdr-async-runner
               (lambda (args callback) (set! fired? #t))))
            (stop-server!))
        """)
        #expect(try engine.evaluate("fired?") == .false)

        // "Stop" clicked → exactly "server stop" fired.
        try engine.evaluate("""
          (define captured #f)
          (parameterize
            ((current-dialog-runner (lambda (cmd cb) (cb 0 "Stop\\n" "")))
             (current-herdr-async-runner
               (lambda (args callback) (set! captured args))))
            (stop-server!))
        """)
        #expect(try engine.evaluate("captured").asString() == "server stop")
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

    /// The `[`/`]` pair is wired into the Panes, Tabs, Workspaces, and
    /// Agents drills — uniform loose keys, each carrying 'next 'self (a
    /// cyclic edge, not a sub-mode to enter) — and deliberately absent from
    /// Worktrees (the human direction named four cycling groups, not five;
    /// prev-next-nav-k4's Notes). Tree-shape assertion, no live herdr.
    @Test func buildHerdrTreeWiresPrevNextCycling() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("""
          (define TREE (build-herdr-tree))
          (define (node-key n) (let ((e (assoc 'key n))) (and e (cdr e))))
          (define (node-with-key k lst)
            (cond ((null? lst) #f)
                  ((equal? (node-key (car lst)) k) (car lst))
                  (else (node-with-key k (cdr lst)))))
          (define (children n) (cdr (assoc 'children n)))
          (define (next-is-self? n) (eq? (cdr (assoc 'next n)) 'self))
        """)
        for drillKey in ["p", "t", "w", "a"] {
            try engine.evaluate("(define KIDS (children (node-with-key \"\(drillKey)\" TREE)))")
            #expect(try engine.evaluate("(if (node-with-key \"[\" KIDS) #t #f)") == .true,
                    "drill \(drillKey) missing [")
            #expect(try engine.evaluate("(if (node-with-key \"]\" KIDS) #t #f)") == .true,
                    "drill \(drillKey) missing ]")
            #expect(try engine.evaluate("(next-is-self? (node-with-key \"[\" KIDS))") == .true,
                    "drill \(drillKey) [ not 'next 'self")
            #expect(try engine.evaluate("(next-is-self? (node-with-key \"]\" KIDS))") == .true,
                    "drill \(drillKey) ] not 'next 'self")
        }
        // Worktrees deliberately excluded.
        try engine.evaluate("(define GKIDS (children (node-with-key \"g\" TREE)))")
        #expect(try engine.evaluate("(if (node-with-key \"[\" GKIDS) #t #f)") == .false)
        #expect(try engine.evaluate("(if (node-with-key \"]\" GKIDS) #t #f)") == .false)
    }

    /// prev-next-nav-k4's "Also": the registered herdr-panes-focus Walk
    /// carries the `[`/`]` pair TOO (added by focus-mode-register!, not
    /// just the Panes drill's own top-level copy), so cycling stays
    /// available mid-focus-walk without leaving it — same 'next 'self
    /// cyclic edge as hjkl.
    @Test func registerInstallsPrevNextInFocusWalk() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("(register!)")
        try engine.evaluate("""
          (define FOCUS (lookup-tree "herdr-panes-focus"))
          (define KIDS (cdr (assoc 'children FOCUS)))
          (define (node-key n) (let ((e (assoc 'key n))) (and e (cdr e))))
          (define (node-with-key k lst)
            (cond ((null? lst) #f)
                  ((equal? (node-key (car lst)) k) (car lst))
                  (else (node-with-key k (cdr lst)))))
        """)
        #expect(try engine.evaluate("(if (node-with-key \"[\" KIDS) #t #f)") == .true)
        #expect(try engine.evaluate("(if (node-with-key \"]\" KIDS) #t #f)") == .true)
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'next (node-with-key \"[\" KIDS))) 'self)") == .true)
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'next (node-with-key \"]\" KIDS))) 'self)") == .true)
    }

    /// Cycling shares the SAME stale-kind guard the digit path uses
    /// (herdr-fast-key-drops-k8): a fast leader→drill→`]` press can reach
    /// the cycling action before THIS kind's on-render-fn ever snapshotted,
    /// so a bare read of the shared current-targets/current-data cell
    /// could silently ring-step another kind's leftover rows. Simulates a
    /// prior Panes render this session, then presses "a" "]" with no
    /// Agents render in between (this harness never opens the overlay): the
    /// kind mismatch must force a fresh `agent list` snapshot before
    /// cycling, exactly like list-digit-range's guard.
    @Test func cyclePressBeforeRenderIgnoresStaleOtherKindEntry() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr)
                  (modaliser blocks herdr-list) (modaliser json))
        """)
        try engine.evaluate("""
          (apply screen 'com.googlecode.iterm2/herdr (build-herdr-tree))
        """)
        // Prior render this session: Panes, one focused row.
        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-list-runner
               (lambda (subcmd)
                 (cond
                   ((string=? subcmd "pane list")
                    (json-parse "{\"result\":{\"panes\":[{\"agent\":\"claude\",\"focused\":true,\"pane_id\":\"STALE-PANE\",\"tab_id\":\"w1:t1\"}]}}"))
                   (else #f)))))
            (herdr-list-refresh! 'panes #f))
        """#)
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'panes)") == .true)

        try engine.evaluate("(modal-enter (lookup-tree \"com.googlecode.iterm2/herdr\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")") // Agents drill — no render yet here

        try engine.evaluate(#"""
          (parameterize
            ((current-herdr-list-runner
               (lambda (subcmd)
                 (cond
                   ((string=? subcmd "agent list")
                    (json-parse "{\"result\":{\"agents\":[{\"agent\":\"a1\",\"agent_status\":\"idle\",\"focused\":true,\"pane_id\":\"REAL-AGENT-1\"},{\"agent\":\"a2\",\"agent_status\":\"idle\",\"focused\":false,\"pane_id\":\"REAL-AGENT-2\"}]}}"))
                   (else #f)))))
            (modal-handle-key "]"))
        """#)

        // The kind mismatch forced a fresh Agents snapshot before cycling —
        // the shared cell no longer belongs to the stale Panes render.
        #expect(try engine.evaluate("(eq? (herdr-list-current-kind) 'agents)") == .true)
        // 'next 'self: firing never pushes/pops — still inside "a".
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"a\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }
}
