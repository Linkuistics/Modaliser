import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("DOM DSL (ui/dom.scm)")
struct DomDslTests {

    private func loadDom() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluateFile(joinPath(schemePath, "lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath, "ui/dom.scm"))
        return engine
    }

    // MARK: - HTML escaping

    @Test func htmlEscapeBasicEntities() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html-escape "<b>Hello & \"World\"</b>")"#)
        #expect(try result.asString() == "&lt;b&gt;Hello &amp; &quot;World&quot;&lt;/b&gt;")
    }

    @Test func htmlEscapeSingleQuote() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html-escape "it's")"#)
        #expect(try result.asString() == "it&#39;s")
    }

    @Test func htmlEscapeEmptyString() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html-escape "")"#)
        #expect(try result.asString() == "")
    }

    // MARK: - Attribute rendering

    @Test func renderAttrsBasic() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(render-attrs '((class . "foo") (id . "bar")))"#)
        #expect(try result.asString() == #" class="foo" id="bar""#)
    }

    @Test func renderAttrsBooleanTrue() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(render-attrs '((disabled . #t)))"#)
        #expect(try result.asString() == " disabled")
    }

    @Test func renderAttrsBooleanFalse() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(render-attrs '((hidden . #f)))"#)
        #expect(try result.asString() == "")
    }

    @Test func renderAttrsEmpty() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(render-attrs '())"#)
        #expect(try result.asString() == "")
    }

    @Test func renderAttrsEscapesValues() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(render-attrs '((title . "a<b")))"#)
        #expect(try result.asString() == #" title="a&lt;b""#)
    }

    // MARK: - Element construction

    @Test func simpleDiv() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (div '() "Hello"))"#)
        #expect(try result.asString() == "<div>Hello</div>")
    }

    @Test func divWithAttributes() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (div '((class . "box")) "content"))"#)
        #expect(try result.asString() == #"<div class="box">content</div>"#)
    }

    @Test func nestedElements() throws {
        let engine = try loadDom()
        let result = try engine.evaluate("""
            (html->string
              (div '((class . "wrapper"))
                (h1 '() "Title")
                (p '() "Body text")))
            """)
        #expect(try result.asString() == #"<div class="wrapper"><h1>Title</h1><p>Body text</p></div>"#)
    }

    @Test func listElements() throws {
        let engine = try loadDom()
        let result = try engine.evaluate("""
            (html->string
              (ul '()
                (li '() "One")
                (li '() "Two")
                (li '() "Three")))
            """)
        #expect(try result.asString() == "<ul><li>One</li><li>Two</li><li>Three</li></ul>")
    }

    @Test func deeplyNested() throws {
        let engine = try loadDom()
        let result = try engine.evaluate("""
            (html->string
              (div '()
                (ul '()
                  (li '()
                    (span '((class . "key")) "s")
                    " Safari"))))
            """)
        #expect(try result.asString() == #"<div><ul><li><span class="key">s</span> Safari</li></ul></div>"#)
    }

    @Test func textIsEscaped() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (p '() "<script>alert('xss')</script>"))"#)
        #expect(try result.asString() == "<p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>")
    }

    // MARK: - Void elements

    @Test func voidElementBr() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (br))"#)
        #expect(try result.asString() == "<br>")
    }

    @Test func voidElementInput() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (input-element '((type . "text") (placeholder . "Search..."))))"#)
        #expect(try result.asString() == #"<input type="text" placeholder="Search...">"#)
    }

    @Test func voidElementImg() throws {
        let engine = try loadDom()
        let result = try engine.evaluate(#"(html->string (img '((src . "icon.png") (alt . "icon"))))"#)
        #expect(try result.asString() == #"<img src="icon.png" alt="icon">"#)
    }

    // MARK: - Document wrapper

    @Test func htmlDocumentWrapper() throws {
        let engine = try loadDom()
        let result = try engine.evaluate("""
            (html-document
              (style-element '() ".key { color: red; }")
              (div '() "Hello"))
            """)
        let str = try result.asString()
        #expect(str.hasPrefix("<!DOCTYPE html><html>"))
        #expect(str.contains("<head><meta charset=\"utf-8\">"))
        #expect(str.contains("<style>.key { color: red; }</style>"))
        #expect(str.contains("<body><div>Hello</div></body>"))
        #expect(str.hasSuffix("</html>"))
    }

    // MARK: - Raw HTML

    @Test func rawHtmlNotDoubleEscaped() throws {
        let engine = try loadDom()
        let result = try engine.evaluate("""
            (html->string
              (div '()
                (span '() "a & b")))
            """)
        let str = try result.asString()
        // The & should be escaped exactly once
        #expect(str.contains("a &amp; b"))
        #expect(!str.contains("&amp;amp;"))
    }

    // MARK: - All convenience functions exist

    @Test func allConvenienceFunctionsAreProcedures() throws {
        let engine = try loadDom()
        let fns = ["div", "span", "p", "a", "h1", "h2", "h3", "ul", "ol", "li",
                    "button", "input-element", "img", "br", "hr",
                    "style-element", "script-element", "section", "header", "footer", "nav"]
        for fn in fns {
            #expect(try engine.evaluate("(procedure? \(fn))") == .true,
                    "Expected \(fn) to be a procedure")
        }
    }
}

enum SchemeTestError: Error {
    case noSchemeDir
}
