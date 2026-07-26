import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

// Embed's in-place activation (embed-rendering-k14; ADR-0011,
// docs/specs/configuration-value.md "The two-layer node model"): the overlay
// renders DISPLAY ROOTS — one persistent layout spanning a node and its
// embedded sections — and the active-section marker restyles as the Visit
// moves. These tests drive the real modal engine end-to-end through the
// overlay's push path (captured webview stubs): navigate in → the section
// activates; backspace → reverts; escape → teardown; the show delay binds to
// the root (no re-arm moving within it); drill behaviour is unchanged for
// non-embedded edges. The payload/serialization contracts live in
// PanelGridRendererTests; the 'embed lowering validation closes this suite.
@Suite("Embed rendering (display roots, in-place activation)")
struct EmbedRenderingTests {

    /// Load all modules including UI, with WebView primitives stubbed to
    /// capture calls: webview-set-html-calls counts full rebuilds,
    /// webview-eval-calls records incremental updateOverlay payloads.
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define webview-eval-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons id webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler) #t)
            (define (webview-eval id js)
              (set! webview-eval-calls (cons js webview-eval-calls)))
            """)
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        try engine.evaluate("(set-overlay-delay! 0)")
        return engine
    }

    /// The shared test config: a global screen embedding "a" (with a plain
    /// non-embedded sibling drill "z" and a loose command "x").
    private func installEmbedConfig(_ engine: SchemeEngine) throws {
        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (screen 'global 'embed '("a")
                (key "x" "Xylophone" (lambda () 'ok))
                (open "a" "Agents"
                  (key "j" "Jump" (lambda () 'ok)))
                (open "z" "Zoo"
                  (key "q" "Quiet" (lambda () 'ok)))))))
            """)
    }

    private func lastEval(_ engine: SchemeEngine) throws -> String {
        try engine.evaluate("(car webview-eval-calls)").asString()
    }

    // MARK: - in-place activation end-to-end

    @Test func navigatingInActivatesSectionInPlace() throws {
        let engine = try loadAllModules()
        try installEmbedConfig(engine)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("(overlay-open?)") == .true)
        let rebuildsAfterShow = try engine.evaluate("(length webview-set-html-calls)")

        // Fire the embedded edge: a REAL Visit moves to the section's state…
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"a\"))") == .true)

        // …but presentation stays on the parent's display root: the update is
        // an incremental push (no full rebuild) whose payload marks the
        // section active and names the same display root.
        #expect(try engine.evaluate("(length webview-set-html-calls)") == rebuildsAfterShow)
        let js = try lastEval(engine)
        #expect(js.contains("\"activeSection\":\"a\""))
        #expect(js.contains("\"rootId\":\"global\""))
        #expect(js.contains("\"sections\":["))
    }

    @Test func backspaceRevertsToAnchorStyling() throws {
        let engine = try loadAllModules()
        try installEmbedConfig(engine)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)
        // The revert is a push for the same root with NO active section.
        let js = try lastEval(engine)
        #expect(js.contains("\"rootId\":\"global\""))
        #expect(!js.contains("\"activeSection\""))
        #expect(js.contains("\"sections\":["))
    }

    @Test func escapeTearsDown() throws {
        let engine = try loadAllModules()
        try installEmbedConfig(engine)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func drillBehaviourUnchangedForNonEmbeddedEdges() throws {
        let engine = try loadAllModules()
        try installEmbedConfig(engine)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        // "z" is NOT in the embed list: an ordinary drill swaps display roots.
        try engine.evaluate("(modal-handle-key \"z\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"z\"))") == .true)
        let js = try lastEval(engine)
        #expect(js.contains("\"rootId\":\"global/z\""))
        #expect(!js.contains("\"activeSection\""))
    }

    @Test func deeperDescentInsideSectionLeavesTheRoot() throws {
        let engine = try loadAllModules()
        // A section's own drill child renders its OWN display root — the
        // persistent root spans one level: the anchor and its sections.
        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (screen 'global 'embed '("a")
                (open "a" "Agents"
                  (open "d" "Deeper"
                    (key "q" "Quiet" (lambda () 'ok))))))))
            """)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        try engine.evaluate("(modal-handle-key \"d\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"a\" \"d\"))") == .true)
        let js = try lastEval(engine)
        #expect(js.contains("\"rootId\":\"global/a/d\""))
        #expect(!js.contains("\"activeSection\""))
    }

    @Test func embeddedPlainGroupKeepsAnchorRendererOnScreen() throws {
        let engine = try loadAllModules()
        // The embedded target here is a PLAIN group (list renderer of its
        // own) — but while it is an active section, the anchor's panel-grid
        // stays on screen, so the update must be an incremental push, not a
        // renderer-swap full rebuild (current-node-renderer anchors).
        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (screen 'global 'embed '("g")
                (group "g" "Plain"
                  (key "p" "Ping" (lambda () 'ok)))))))
            """)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        let rebuildsAfterShow = try engine.evaluate("(length webview-set-html-calls)")
        try engine.evaluate("(modal-handle-key \"g\")")
        #expect(try engine.evaluate("(length webview-set-html-calls)") == rebuildsAfterShow)
        let js = try lastEval(engine)
        #expect(js.contains("\"activeSection\":\"g\""))
        #expect(js.contains("\"label\":\"Ping\""))
    }

    // MARK: - show delay binds to the display root

    @Test func embeddedDescentDoesNotReArmShowDelay() throws {
        let engine = try loadAllModules()
        try installEmbedConfig(engine)
        // A long delay keeps the overlay closed for the whole test; the
        // generation counter is the re-arm observable (every re-arm bumps it
        // to invalidate the pending callback).
        try engine.evaluate("(set-overlay-delay! 30)")
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("(overlay-open?)") == .false)
        let genAfterActivate = try engine.evaluate("modal-overlay-generation")

        // Moving INTO the embedded section stays within the display root: the
        // delay armed for the root's first display keeps its deadline.
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("modal-overlay-generation") == genAfterActivate)
        #expect(try engine.evaluate("(overlay-open?)") == .false)

        // Backspace within the root: still no re-arm.
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-overlay-generation") == genAfterActivate)

        // A NON-embedded drill swaps roots and re-arms as before.
        try engine.evaluate("(modal-handle-key \"z\")")
        #expect(try engine.evaluate("modal-overlay-generation") != genAfterActivate)
    }

    // MARK: - embed references are load-time errors

    @Test func embedKeyNamingNoChildRejectsAtConstruction() throws {
        let engine = try loadAllModules()
        // The sugar attaches its display via with-display, which
        // validates references at the attach (display-dsl-surface-k23) —
        // so a dangling embed key rejects at the (screen …) form itself,
        // before any lowering.
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
                (configuration
                  (screen 'bad 'embed '("q")
                    (key "x" "X" (lambda () 'ok))))
                """)
        }
    }

    @Test func embedKeyNamingALeafRejectsAtConstruction() throws {
        let engine = try loadAllModules()
        // A section is an intra-tree drill target: a command leaf cannot be
        // embedded (that would be a splice's job). Rejected by the sugar's
        // with-display attach, like the dangling key above.
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
                (configuration
                  (screen 'bad2 'embed '("x")
                    (key "x" "X" (lambda () 'ok))))
                """)
        }
    }

    @Test func embedKeyStillRejectsAtLoweringForHandBuiltDisplays() throws {
        let engine = try loadAllModules()
        // lower-node!'s own embed check remains the backstop for a
        // display attached WITHOUT with-display's validation (raw
        // node-with-display — tooling, hand-built alists): still a
        // load-time error, at the lowering.
        try engine.evaluate("""
            (define (lowering-errors? cfg)
              (guard (e (#t #t))
                (lower-configuration cfg)
                #f))
            """)
        #expect(try engine.evaluate("""
            (lowering-errors? (configuration
              (tree 'bad3
                (node-with-display
                  (tree-root 'bad3 (key "x" "X" (lambda () 'ok)))
                  '((embed . ("x")))))))
            """) == .true)
    }

    @Test func embedKeyNamingAGroupChildLowersCleanly() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define g (lower-configuration (configuration
              (screen 'good 'embed '("a")
                (open "a" "Agents"
                  (key "j" "Jump" (lambda () 'ok)))))))
            """)
        #expect(try engine.evaluate("(fsm-graph? g)") == .true)
    }
}
