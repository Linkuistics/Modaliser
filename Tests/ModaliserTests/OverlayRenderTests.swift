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

    // MARK: - Multi-column layout (overlay-column-count)

    /// Defaults: aspect ratio = 1.6, col-width = 200px, row-height = 22px.
    /// overlay-column-count picks the N that minimises |ratio(N) - target|.
    /// Each pair below is (item-count, expected-cols).
    @Test func overlayColumnCountPicksClosestToTargetRatio() throws {
        let engine = try loadOverlay()
        let cases: [(Int, Int)] = [
            (0, 1), (1, 1), (2, 1),   // never more cols than items
            (5, 1), (10, 1),          // short lists stay one column
            (20, 2),                  // medium → 2
            (50, 3),                  // big   → 3
            (100, 4),                 // huge  → 4
        ]
        for (n, want) in cases {
            let got = try engine.evaluate("(overlay-column-count \(n))").asInt64()
            #expect(Int(got) == want, "n=\(n): expected \(want) cols, got \(got)")
        }
    }

    @Test func renderOverlayBodyEmitsColumnCountStyle() throws {
        let engine = try loadOverlay()
        // 20 entries → 2 cols at default 1.6 ratio (see other test).
        var keys = "abcdefghijklmnopqrst"
        var bindings = ""
        for c in keys { bindings += "(key \"\(c)\" \"\(c)\" (lambda () 'ok)) " }
        try engine.evaluate("(define-tree 'global \(bindings))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        #expect(html.contains("--overlay-cols: 2"),
                "Expected --overlay-cols: 2 inline on .overlay-entries; got HTML did not match")
    }

    @Test func overlayColumnCountFollowsTargetAspectRatio() throws {
        let engine = try loadOverlay()
        // Wide target → prefer more columns. n=10 at ratio 5.0 should jump
        // to 2 cols because the wider target needs the extra width.
        try engine.evaluate("(set-overlay-aspect-ratio! 5.0)")
        let wide = try engine.evaluate("(overlay-column-count 10)").asInt64()
        #expect(wide >= 2, "ratio 5.0, n=10 should pick ≥2 cols, got \(wide)")
        // Tall target → 1 col for everything reasonable.
        try engine.evaluate("(set-overlay-aspect-ratio! 0.2)")
        let tall = try engine.evaluate("(overlay-column-count 20)").asInt64()
        #expect(tall == 1, "ratio 0.2, n=20 should pick 1 col, got \(tall)")
    }

    @Test func renderOverlayHtmlProducesValidDocument() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
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
            (define-tree 'global
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
            (define-tree 'global
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
            (define-tree 'global
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
            (define-tree 'global
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
        #expect(footer.contains("class=\"sigil\">\u{238B}"))
        #expect(footer.contains("class=\"sigil sigil-back\">\u{232B}"))
    }

    @Test func renderOverlayHtmlPaintsStickyMarkerOnTaggedKeys() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
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
            (define-tree 'global
              (key "z" "Zoom" (lambda () 'ok))
              (key "a" "Alacritty" (lambda () 'ok))
              (key "m" "Messages" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // 'a' should appear before 'm', and 'm' before 'z'
        let aPos = html.range(of: "Alacritty")!.lowerBound
        let mPos = html.range(of: "Messages")!.lowerBound
        let zPos = html.range(of: "Zoom")!.lowerBound
        #expect(aPos < mPos)
        #expect(mPos < zPos)
    }

    @Test func renderOverlayHtmlShowsGroupWithEllipsis() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // Group entries show label with ellipsis and group-label class
        #expect(html.contains("Windows \u{2026}"))
        #expect(html.contains("group-label"))
    }

    @Test func renderOverlayHtmlWithPath() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
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
            (define-tree 'global
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
            (define-tree 'global
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
            (define-tree 'global
              (key "s" "Open <Script>" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // Label should be HTML-escaped
        #expect(html.contains("&lt;Script&gt;"))
        #expect(!html.contains("<Script>"))
    }

    @Test func renderOverlayHtmlSpaceKeyDisplaysSymbol() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
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

    @Test func setHostHeaderStoresAllThreeFields() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (set-host-header!
              'name "my-server"
              'background "#7a1f3d"
              'foreground "#ffffff")
            """)
        #expect(try engine.evaluate("host-header-name").asString() == "my-server")
        #expect(try engine.evaluate("host-header-background").asString() == "#7a1f3d")
        #expect(try engine.evaluate("host-header-foreground").asString() == "#ffffff")
    }

    @Test func setHostHeaderAcceptsNameOnly() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"local\")")
        #expect(try engine.evaluate("host-header-name").asString() == "local")
        #expect(try engine.evaluate("host-header-background") == .false)
        #expect(try engine.evaluate("host-header-foreground") == .false)
    }

    @Test func setHostHeaderRejectsUnknownKeyword() throws {
        let engine = try loadOverlay()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-host-header! 'name \"x\" 'unknown 1)")
        }
    }

    @Test func setHostHeaderTrimsWhitespaceFromAllValues() throws {
        // (run-shell "hostname -s") and similar return a trailing newline;
        // callers shouldn't have to know to trim before passing.
        let engine = try loadOverlay()
        try engine.evaluate("""
            (set-host-header!
              'name            "  Bach\\n"
              'background      "  steelblue\\n"
              'foreground      "  white\\n"
              'separator-color "  #888\\n")
            """)
        #expect(try engine.evaluate("host-header-name").asString() == "Bach")
        #expect(try engine.evaluate("host-header-background").asString() == "steelblue")
        #expect(try engine.evaluate("host-header-foreground").asString() == "white")
        #expect(try engine.evaluate("host-header-separator-color").asString() == "#888")
    }

    @Test func setHostHeaderSeparatorColorIsOptional() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\")")
        #expect(try engine.evaluate("host-header-separator-color") == .false)
    }

    @Test func hostHeaderCssEmitsSeparatorVariableWhenSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\" 'separator-color \"#abc\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains("--color-host-sep: #abc"))
    }

    @Test func hostHeaderCssEmptyWhenNoColoursSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css == "")
    }

    @Test func hostHeaderCssEmitsBothVariables() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (set-host-header! 'name "x" 'background "#000" 'foreground "#fff")
            """)
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains(":root"))
        #expect(css.contains("--color-host-bg: #000"))
        #expect(css.contains("--color-host-fg: #fff"))
    }

    @Test func backgroundOnlySetsForegroundToWhiteDefault() throws {
        // Seed-config use case: callers thread the theme through by
        // supplying 'background; foreground defaults to "white" so the
        // header reads against the coloured chip without callers having
        // to spell it out.
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\" 'background \"#abc\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains("--color-host-bg: #abc"))
        #expect(css.contains("--color-host-fg: white"))
    }

    @Test func backgroundDefaultForegroundIsOverridable() throws {
        // Explicit 'foreground wins over the implicit "white" that kicks
        // in when only 'background is supplied.
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\" 'background \"#abc\" 'foreground \"#000\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains("--color-host-fg: #000"))
        #expect(!css.contains("--color-host-fg: white"))
    }

    @Test func nameDefaultsToShellHostname() throws {
        // With no 'name supplied, the library calls (run-shell "hostname -s")
        // so the seed config can be a one-liner.
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header!)")
        let name = try engine.evaluate("host-header-name").asString()
        #expect(!name.isEmpty)
        #expect(!name.contains("\n"))
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
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(alist-ref (lookup-tree \"global\") 'scope #f)").asString()
                  == "global")

        try engine.evaluate("(define-tree 'com.apple.Safari (key \"t\" \"Tabs\" (lambda () 'ok)))")
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

    @Test func computeRootSegmentsPrependsHostWhenSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"my-server\")")
        try engine.evaluate("""
            (define (app-display-name id)
              (if (equal? id "com.googlecode.iterm2") "iTerm" #f))
            """)
        // List → ("my-server" "iTerm" "nvim"). Pre-bind to a Scheme variable
        // so the assertions can index into it without re-evaluating the expression.
        try engine.evaluate("""
            (define segs (compute-root-segments "com.googlecode.iterm2/nvim"))
            """)
        #expect(try engine.evaluate("(length segs)") == .fixnum(3))
        #expect(try engine.evaluate("(list-ref segs 0)").asString() == "my-server")
        #expect(try engine.evaluate("(list-ref segs 1)").asString() == "iTerm")
        #expect(try engine.evaluate("(list-ref segs 2)").asString() == "nvim")
    }

    @Test func modalEnterPopulatesRootSegments() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"box\")")
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        // Stub the keymap registrations (modal-enter calls register-all-keys!).
        try engine.evaluate("(define (register-all-keys! h) #t)")
        try engine.evaluate("(define (unregister-all-keys!) #t)")
        try engine.evaluate("(modal-enter (lookup-tree \"global\") 0)")
        let len = try engine.evaluate("(length (modal-root-segments))")
        #expect(len == .fixnum(2))
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 0)").asString() == "box")
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 1)").asString() == "Global")
    }

    @Test func modalExitPreservesRootSegmentsForChooserHandoff() throws {
        // Selector keys call (modal-exit) immediately before (open-chooser …),
        // and the chooser reads modal-root-segments to render its breadcrumb.
        // If modal-exit cleared the segments the chooser would lose host + scope.
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"box\")")
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        try engine.evaluate("(define (register-all-keys! h) #t)")
        try engine.evaluate("(define (unregister-all-keys!) #t)")
        try engine.evaluate("(modal-enter (lookup-tree \"global\") 0)")
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("(length (modal-root-segments))") == .fixnum(2))
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 0)").asString() == "box")
        #expect(try engine.evaluate("(list-ref (modal-root-segments) 1)").asString() == "Global")
    }

    @Test func renderOverlayHtmlPrependsHostSegment() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
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
            "(define-tree 'com.googlecode.iterm2/nvim (key \"x\" \"X\" (lambda () 'ok)))")
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
            (define-tree 'global
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

    @Test func renderOverlayHtmlIncludesHostCssWhenColoursSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate(
            "(set-host-header! 'name \"x\" 'background \"#abc\" 'foreground \"#def\")")
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("x" "Global") '())
            """).asString()
        #expect(html.contains("--color-host-bg: #abc"))
        #expect(html.contains("--color-host-fg: #def"))
    }

    @Test func renderOverlayHtmlOmitsHostCssWhenNotSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(define-tree 'global (key \"s\" \"Safari\" (lambda () 'ok)))")
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        // Variables are referenced in base.css with fallbacks, but not assigned when not set
        #expect(!html.contains("--color-host-bg:"))
        #expect(!html.contains("--color-host-fg:"))
    }
}
