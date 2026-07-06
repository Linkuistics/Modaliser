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
        // The only public exports are register! and backend; per ADR-0003
        // the ops live on the façade. Both must bind without error.
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

    /// (register!) also wires the digit-pick mode so the façade's
    /// (focus-pane-by-digit) thunk has a tree to (enter-mode!) into.
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

    /// `build-herdr-tree` now returns the full herdr surface, not the hjkl
    /// skeleton: a Focus panel, the x Split / m Move groups, z/d pane keys,
    /// the t Tabs / w Workspaces drills, and the Panes list panel — eight
    /// top-level nodes. It must build without touching herdr (all shell-outs
    /// live in on-render thunks / key actions, never at construction time).
    @Test func buildHerdrTreeIsFullSurface() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        #expect(try engine.evaluate("(length (build-herdr-tree))") == .fixnum(8))
    }

    /// (register!) wires the sticky top-level focus mode the herdr tree's
    /// Focus panel latches into ('sticky-target 'herdr-panes-focus), so a
    /// first hjkl focuses AND keeps moving without another leader press.
    @Test func registerInstallsStickyFocusMode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser muxes herdr))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"herdr-panes-focus\")") != .false)
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
          (define R (herdr-list-extract 'panes (list "1" "2" "3") J))
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
          (define RT (herdr-list-extract 'tabs (list "1" "2") JT))
        """#)
        #expect(try engine.evaluate("(cdr (assoc \"2\" (car RT)))") == .string("w9:t2"))
        #expect(try engine.evaluate("(cdr (assoc 'title (car (cdr RT))))") == .string("1 claude"))
        // Workspaces.
        try engine.evaluate(#"""
          (define JW (json-parse "{\"result\":{\"workspaces\":[{\"focused\":true,\"label\":\"TestAnyware\",\"workspace_id\":\"w9\"}]}}"))
          (define RW (herdr-list-extract 'workspaces (list "1") JW))
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
        try engine.evaluate("(define R (herdr-list-extract 'panes (list \"1\" \"2\") #f))")
        #expect(try engine.evaluate("(null? (car R))") == .true)
        #expect(try engine.evaluate("(null? (cdr R))") == .true)
    }
}
