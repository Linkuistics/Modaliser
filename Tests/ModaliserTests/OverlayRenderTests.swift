import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay Rendering (ui/overlay.scm)")
struct OverlayRenderTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser dom))")
        let files = [
            "ui/css.scm",
            "ui/overlay.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - render-overlay-html (pure)

    // MARK: - render-overlay-html key-column width (data-key-ch)

    @Test func renderOverlayBodyEmitsKeyChFromWidestKey() throws {
        let engine = try loadOverlay()
        // "abc" is a 3-char display-key — widest among the entries; the
        // grid first track is pinned to 3ch so the arrow column aligns
        // across all entries regardless of which CSS-multi-column column
        // they land in.
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key "a" "Apple" (lambda () 'ok))
              (key "abc" "Three-char" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        #expect(html.contains("data-key-ch=\"3\""),
                "Expected data-key-ch=\"3\" attribute (widest key 'abc'); got HTML did not match")
    }

    @Test func renderOverlayBodyKeyChClampsToTwo() throws {
        let engine = try loadOverlay()
        // All single-char keys — the clamp keeps the key column at 2ch
        // for breathing room before the arrow track.
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key "a" "Apple" (lambda () 'ok))
              (key "b" "Banana" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        #expect(html.contains("data-key-ch=\"2\""),
                "Expected data-key-ch=\"2\" attribute (single-char keys clamp to min 2); got HTML did not match")
    }

    @Test func renderOverlayHtmlProducesValidDocument() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key "s" "Safari" (lambda () 'ok))
              (key "f" "Finder" (lambda () 'ok)))
            """)
        let result = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """)
        let html = try result.asString()
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<div class=\"overlay\">"))
        #expect(html.contains("Global"))
    }

    @Test func renderOverlayHtmlShowsEntries() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key "s" "Safari" (lambda () 'ok))
              (key "f" "Finder" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        #expect(html.contains("Safari"))
        #expect(html.contains("Finder"))
        #expect(html.contains("entry-key"))
        #expect(html.contains("entry-arrow"))
    }

    /// Returns the inner text of the overlay-footer div, or nil if missing.
    /// Tolerates additional modifier classes (e.g. overlay-footer-root).
    private func extractFooter(_ html: String) -> String? {
        guard let classStart = html.range(of: "class=\"overlay-footer")?.lowerBound,
              let openClose = html.range(of: "\">", range: classStart..<html.endIndex)?.upperBound,
              let end = html.range(of: "</div>", range: openClose..<html.endIndex)?.lowerBound
        else { return nil }
        return String(html[openClose..<end])
    }

    @Test func renderOverlayFooterAtRootOmitsBackspaceHint() throws {
        // At the root of a tree, backspace doesn't apply (transient roots
        // are a no-op for back, sticky roots only pop modal-stack in the
        // uncommon enter-mode! caller case), so the hint is omitted.
        // Sigils: ⎋ (U+238B) for escape, ⌫ (U+232B) for backspace.
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        let footer = try #require(extractFooter(html))
        #expect(footer.contains("\u{238B}"))
        #expect(!footer.contains("\u{232B}"))
        // Root footer carries the right-align modifier class — the class
        // attribute on the <div> includes overlay-footer-root.
        #expect(html.contains("class=\"overlay-footer overlay-footer-root\""))
    }

    @Test func renderOverlayFooterDeepOmitsRootModifier() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '("w"))
            """).asString()
        // Deep footer should have the plain class, not the root modifier.
        #expect(html.contains("class=\"overlay-footer\">"))
        #expect(!html.contains("class=\"overlay-footer overlay-footer-root\""))
    }

    @Test func renderOverlayFooterInGroupShowsBackspaceHint() throws {
        // Below the root, backspace navigates back up — surface the hint.
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '("w"))
            """).asString()
        let footer = try #require(extractFooter(html))
        #expect(footer.contains("\u{238B}"))
        #expect(footer.contains("\u{232B}"))
        // Both sigils must be wrapped in a span carrying .sigil so base.css
        // can enlarge + bold them — otherwise they render at the footer's
        // (smaller) default and visually disappear. The backspace also
        // carries .sigil-back for its extra +2px size bump.
        #expect(footer.contains("class=\"sigil sigil-escape\">\u{238B}"))
        #expect(footer.contains("class=\"sigil sigil-back\">\u{232B}"))
    }

    @Test func renderOverlayHtmlPaintsStickyMarkerOnTaggedKeys() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key "h" "Focus Left" (lambda () 'ok)
                'sticky-target 'iterm-panes-focus)
              (key "c" "Copy" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // The sticky-target leaf gets a marker; plain keys don't.
        #expect(html.contains("entry-sticky-marker"))
        // The marker character (↻) is U+21BB
        #expect(html.contains("\u{21BB}"))
    }

    @Test func renderOverlayHtmlSortsEntriesByKey() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key "z" "Zoom" (lambda () 'ok))
              (key "a" "Alacritty" (lambda () 'ok))
              (key "m" "Messages" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        // 'a' should appear before 'm', and 'm' before 'z'
        let aPos = html.range(of: "Alacritty")!.lowerBound
        let mPos = html.range(of: "Messages")!.lowerBound
        let zPos = html.range(of: "Zoom")!.lowerBound
        #expect(aPos < mPos)
        #expect(mPos < zPos)
    }

    @Test func renderOverlayHtmlCaseAwareSort() throws {
        let engine = try loadOverlay()
        // Mixed-case keys: expected order is a, A, b, B — case-insensitive
        // primary, lowercase-first tiebreak. Source order is shuffled so
        // a passing test really proves the sort fires.
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key "B" "BravoUpper" (lambda () 'ok))
              (key "a" "AlphaLower" (lambda () 'ok))
              (key "A" "AlphaUpper" (lambda () 'ok))
              (key "b" "BravoLower" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("G") '())
            """).asString()
        let aLow = html.range(of: "AlphaLower")!.lowerBound
        let aUp  = html.range(of: "AlphaUpper")!.lowerBound
        let bLow = html.range(of: "BravoLower")!.lowerBound
        let bUp  = html.range(of: "BravoUpper")!.lowerBound
        #expect(aLow < aUp)
        #expect(aUp < bLow)
        #expect(bLow < bUp)
    }

    @Test func renderOverlayHtmlOrderDeclaredPreservesAuthoredOrder() throws {
        let engine = try loadOverlay()
        // A group carrying 'order 'declared (e.g. a sticky-set walk registered
        // with 'order 'declared) renders rows in declaration order, opting out
        // of the default key-sort (iterm-nav-declared-order-k38). Keys are
        // shuffled so a pass really proves the sort was skipped.
        try engine.evaluate("""
            (register-tree! 'walk-declared 'order 'declared
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "walk-declared") '("Walk") '())
            """).asString()
        // Declaration order: Zulu before Alpha (the default sort would invert).
        let zPos = html.range(of: "Zulu")!.lowerBound
        let aPos = html.range(of: "Alpha")!.lowerBound
        #expect(zPos < aPos)
    }

    @Test func renderOverlayHtmlNoOrderStillSortsByKey() throws {
        let engine = try loadOverlay()
        // Control: a registered group with no 'order keeps key-sorting (the
        // default), so 'order 'declared is genuinely opt-in.
        try engine.evaluate("""
            (register-tree! 'walk-default
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "walk-default") '("Walk") '())
            """).asString()
        let zPos = html.range(of: "Zulu")!.lowerBound
        let aPos = html.range(of: "Alpha")!.lowerBound
        #expect(aPos < zPos)
    }

    @Test func renderOverlayHtmlShowsGroupWithEllipsis() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok)))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        // Group entries show label with ellipsis and group-label class
        #expect(html.contains("Windows \u{2026}"))
        #expect(html.contains("group-label"))
    }

    @Test func renderOverlayHtmlWithPath() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (key "m" "Maximize" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '("w"))
            """).asString()
        // Should show Windows' children, not root
        #expect(html.contains("Center"))
        #expect(html.contains("Maximize"))
        // Breadcrumb path is rendered with the group's label, not the key char.
        #expect(html.contains("Global"))
        #expect(html.contains("Windows"))
    }

    @Test func renderOverlayHtmlPathRendersLabelsNotKeyChars() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (group "w" "Windows"
                (group "x" "Layouts"
                  (key "c" "Center" (lambda () 'ok)))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '("w" "x"))
            """).asString()
        // Specifically inspect the breadcrumb element so we don't pick up the
        // group's `data-key` or single-char fragments anywhere else in the HTML.
        let breadcrumb = String(html[html.range(of: "<header")!.lowerBound ..<
                                     html.range(of: "</header>")!.upperBound])
        #expect(breadcrumb.contains("Windows"))
        #expect(breadcrumb.contains("Layouts"))
        #expect(!breadcrumb.contains(">w<"))
        #expect(!breadcrumb.contains(">x<"))
    }

    @Test func renderOverlayHtmlIncludesCSS() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // Should include base.css content in a style tag
        #expect(html.contains("<style>"))
        #expect(html.contains("--overlay-bg"))
    }

    @Test func renderOverlayHtmlEscapesLabelContent() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key "s" "Open <Script>" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        // Label should be HTML-escaped
        #expect(html.contains("&lt;Script&gt;"))
        #expect(!html.contains("<Script>"))
    }

    @Test func renderOverlayHtmlSpaceKeyDisplaysSymbol() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (register-tree! 'global
              (key " " "Space action" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        #expect(html.contains("\u{2423}"))
    }

    // MARK: - Overlay state

    @Test func overlayProceduresExist() throws {
        let engine = try loadOverlay()
        #expect(try engine.evaluate("(procedure? show-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? update-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? hide-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? render-overlay-html)") == .true)
    }

    @Test func overlayStartsClosed() throws {
        let engine = try loadOverlay()
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func resolveAppSegmentsResolvesPlainBundleId() throws {
        let engine = try loadOverlay()
        // Stub the Swift native function with a Scheme one for predictability.
        try engine.evaluate("""
            (define (app-display-name id)
              (cond ((equal? id "com.apple.Safari") "Safari")
                    ((equal? id "com.googlecode.iterm2") "iTerm")
                    (else #f)))
            """)
        #expect(try engine.evaluate("(resolve-app-segments \"com.apple.Safari\")")
                  == .pair(.makeString("Safari"), .null))
    }

    @Test func resolveAppSegmentsSplitsVariant() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define (app-display-name id)
              (if (equal? id "com.googlecode.iterm2") "iTerm" #f))
            """)
        let result = try engine.evaluate(
            "(resolve-app-segments \"com.googlecode.iterm2/nvim\")")
        // Expect ("iTerm" "nvim") as a Scheme list.
        #expect(result == .pair(.makeString("iTerm"),
                                 .pair(.makeString("nvim"), .null)))
    }

    @Test func resolveAppSegmentsFallsBackToBundleIdWhenUnresolvable() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(define (app-display-name id) #f)")
        #expect(try engine.evaluate("(resolve-app-segments \"com.example.unknown\")")
                  == .pair(.makeString("com.example.unknown"), .null))
    }

    @Test func registerTreeStoresScopeOnRoot() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(register-tree! 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(alist-ref (lookup-tree \"global\") 'scope #f)").asString()
                  == "global")

        try engine.evaluate("(register-tree! 'com.apple.Safari (key \"t\" \"Tabs\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(alist-ref (lookup-tree \"com.apple.Safari\") 'scope #f)").asString()
                  == "com.apple.Safari")
    }

    @Test func computeRootSegmentsGlobalNoHost() throws {
        let engine = try loadOverlay()
        let result = try engine.evaluate("(compute-root-segments \"global\")")
        #expect(result == .pair(.makeString("Global"), .null))
    }

    @Test func computeRootSegmentsAppNoHost() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define (app-display-name id)
              (if (equal? id "com.apple.Safari") "Safari" #f))
            """)
        let result = try engine.evaluate("(compute-root-segments \"com.apple.Safari\")")
        #expect(result == .pair(.makeString("Safari"), .null))
    }

    @Test func modalEnterPopulatesRootSegments() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(register-tree! 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        // Stub the keymap registrations (modal-enter calls register-all-keys!).
        try engine.evaluate("(define (register-all-keys! h) #t)")
        try engine.evaluate("(define (unregister-all-keys!) #t)")
        try engine.evaluate("(modal-enter (lookup-tree \"global\") 0)")
        #expect(try engine.evaluate("(length (modal-root-segments))") == .fixnum(1))
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 0)").asString() == "Global")
    }

    @Test func modalExitPreservesRootSegmentsForChooserHandoff() throws {
        // Selector keys call (modal-exit) immediately before (open-chooser …),
        // and the chooser reads modal-root-segments to render its breadcrumb.
        // If modal-exit cleared the segments the chooser would lose the scope.
        let engine = try loadOverlay()
        try engine.evaluate("(register-tree! 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        try engine.evaluate("(define (register-all-keys! h) #t)")
        try engine.evaluate("(define (unregister-all-keys!) #t)")
        try engine.evaluate("(modal-enter (lookup-tree \"global\") 0)")
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("(length (modal-root-segments))") == .fixnum(1))
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 0)").asString() == "Global")
    }

    @Test func renderOverlayHtmlPrependsHostSegment() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(register-tree! 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("my-server" "Global") '("w"))
            """).asString()
        #expect(html.contains("my-server"))
        #expect(html.contains("Global"))
        #expect(html.contains("breadcrumb-sep"))
    }

    @Test func renderOverlayHtmlVariantSegmentsRendered() throws {
        let engine = try loadOverlay()
        try engine.evaluate(
            "(register-tree! 'com.googlecode.iterm2/nvim (key \"x\" \"X\" (lambda () 'ok)))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "com.googlecode.iterm2/nvim")
                                 '("iTerm" "nvim") '())
            """).asString()
        #expect(html.contains("iTerm"))
        #expect(html.contains("nvim"))
    }

    @Test func pushOverlayUpdateEmitsRootSegmentsArray() throws {
        // Stub webview-eval BEFORE loading modules so the native binding is
        // shadowed for the duration of the test.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("""
            (define last-eval-js #f)
            (define (webview-eval id js) (set! last-eval-js js))
            """)
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser dom))")
        let files = [
            "ui/css.scm",
            "ui/overlay.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        try engine.evaluate("""
            (register-tree! 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)
        try engine.evaluate("(set-overlay-open! #t)")
        // push-overlay-update reads modal-root-segments — set it manually for the test.
        try engine.evaluate("(set-modal-root-segments! '(\"my-server\" \"Global\"))")
        try engine.evaluate("(push-overlay-update (lookup-tree \"global\") '(\"w\"))")
        let js = try engine.evaluate("last-eval-js").asString()
        #expect(js.contains("rootSegments"))
        #expect(js.contains("my-server"))
        #expect(js.contains("Global"))
        // Path is sent as labels, not raw key chars.
        #expect(js.contains("\"path\":[\"Windows\"]"))
        #expect(!js.contains("\"path\":[\"w\"]"))
    }

    @Test func renderOverlayHtmlOmitsHostCssWhenNotSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(register-tree! 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // Variables are referenced in base.css with fallbacks, but not assigned when not set
        #expect(!html.contains("--color-host-bg:"))
        #expect(!html.contains("--color-host-fg:"))
    }
}
