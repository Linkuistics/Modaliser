import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay asset registration (add-overlay-asset!)")
struct OverlayAssetRegistrationTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    @Test func registeredCssAppearsInRenderedHtml() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (add-overlay-asset! 'css ".my-marker { color: tomato; }")
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains(".my-marker { color: tomato; }"))
    }

    @Test func registeredJsAppearsInRenderedHtml() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (add-overlay-asset! 'js "window.testMarker = 42;")
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("window.testMarker = 42;"))
    }

    @Test func multipleAssetsOfSameKindConcatenateInOrder() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (add-overlay-asset! 'css "/* first */")
          (add-overlay-asset! 'css "/* second */")
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        let firstIdx = html.range(of: "/* first */")!.lowerBound
        let secondIdx = html.range(of: "/* second */")!.lowerBound
        #expect(firstIdx < secondIdx)
    }

    @Test func userOverrideCssAppliesAfterExtras() throws {
        let engine = try loadOverlay()
        // overlay-custom-css is populated at boot by root.scm slurping
        // ~/.config/modaliser/overlay.css. The setter was removed in
        // the chip-theming refactor; tests poke the variable directly.
        try engine.evaluate("""
          (add-overlay-asset! 'css "/* extra */")
          (set! overlay-custom-css "/* user */")
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        let extraIdx = html.range(of: "/* extra */")!.lowerBound
        let userIdx = html.range(of: "/* user */")!.lowerBound
        #expect(extraIdx < userIdx)
    }
}
