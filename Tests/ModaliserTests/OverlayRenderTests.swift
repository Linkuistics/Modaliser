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
        let files = [
            "lib/util.scm",
            "core/keymap.scm",
            "ui/dom.scm",
            "ui/css.scm",
            "core/state-machine.scm",
            "core/event-dispatch.scm",
            "ui/overlay.scm",
            "lib/dsl.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - render-overlay-html (pure)

    @Test func renderOverlayHtmlProducesValidDocument() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (key "f" "Finder" (lambda () 'ok)))
            """)
        let result = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
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
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        #expect(html.contains("Safari"))
        #expect(html.contains("Finder"))
        #expect(html.contains("entry-key"))
        #expect(html.contains("entry-arrow"))
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
            (render-overlay-html (lookup-tree "global") '())
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
            (render-overlay-html (lookup-tree "global") '())
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
            (render-overlay-html (lookup-tree "global") '("w"))
            """).asString()
        // Should show Windows' children, not root
        #expect(html.contains("Center"))
        #expect(html.contains("Maximize"))
        // Header should show breadcrumb with Global > w
        #expect(html.contains("Global"))
        #expect(html.contains("w"))
    }

    @Test func renderOverlayHtmlIncludesCSS() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
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
            (render-overlay-html (lookup-tree "global") '())
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
            (render-overlay-html (lookup-tree "global") '())
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
        #expect(try engine.evaluate("overlay-open?") == .false)
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

    @Test func hostHeaderCssEmitsOnlyTheSetVariable() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\" 'background \"#abc\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains("--color-host-bg: #abc"))
        #expect(!css.contains("--color-host-fg"))
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
        let len = try engine.evaluate("(length modal-root-segments)")
        #expect(len == .fixnum(2))
        #expect(try engine.evaluate("(list-ref modal-root-segments 0)").asString() == "box")
        #expect(try engine.evaluate("(list-ref modal-root-segments 1)").asString() == "Global")
        try engine.evaluate("(modal-exit)")
        let lenAfter = try engine.evaluate("(length modal-root-segments)")
        #expect(lenAfter == .fixnum(0))
    }
}
