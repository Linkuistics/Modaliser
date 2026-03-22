import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("CSS DSL (ui/css.scm)")
struct CssDslTests {

    private func loadCss() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluateFile(joinPath(schemePath, "lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath, "ui/css.scm"))
        return engine
    }

    // MARK: - css-rule

    @Test func cssRuleBasic() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rule ".key" '((background . "#333") (padding . "2px 6px")))
            """)
        #expect(try result.asString() == ".key { background: #333; padding: 2px 6px; }")
    }

    @Test func cssRuleSingleProperty() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rule "body" '((margin . "0")))
            """)
        #expect(try result.asString() == "body { margin: 0; }")
    }

    @Test func cssRuleWithHyphenatedProperty() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rule ".box" '((border-radius . "8px") (font-size . "14px")))
            """)
        #expect(try result.asString() == ".box { border-radius: 8px; font-size: 14px; }")
    }

    @Test func cssRuleEmptyProperties() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rule ".empty" '())
            """)
        #expect(try result.asString() == ".empty {  }")
    }

    // MARK: - css-rules

    @Test func cssRulesMultiple() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rules
              (css-rule "body" '((margin . "0")))
              (css-rule ".key" '((color . "white"))))
            """)
        let str = try result.asString()
        #expect(str.contains("body { margin: 0; }"))
        #expect(str.contains(".key { color: white; }"))
    }

    @Test func cssRulesSingle() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (css-rules (css-rule "body" '((margin . "0"))))
            """)
        #expect(try result.asString() == "body { margin: 0; }")
    }

    // MARK: - inline-style

    @Test func inlineStyleBasic() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (inline-style '((color . "red") (font-size . "14px")))
            """)
        #expect(try result.asString() == "color: red; font-size: 14px;")
    }

    @Test func inlineStyleSingle() throws {
        let engine = try loadCss()
        let result = try engine.evaluate("""
            (inline-style '((display . "none")))
            """)
        #expect(try result.asString() == "display: none;")
    }

    // MARK: - Procedure checks

    @Test func allCssProceduresExist() throws {
        let engine = try loadCss()
        #expect(try engine.evaluate("(procedure? css-rule)") == .true)
        #expect(try engine.evaluate("(procedure? css-rules)") == .true)
        #expect(try engine.evaluate("(procedure? inline-style)") == .true)
    }
}
