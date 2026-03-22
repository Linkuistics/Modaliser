import Testing
import LispKit
@testable import Modaliser

@Suite("WebView Library")
struct WebViewLibraryTests {

    // MARK: - Library registration

    @Test func webviewFunctionsExist() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("webview-create")
        _ = try engine.evaluate("webview-close")
        _ = try engine.evaluate("webview-set-html!")
        _ = try engine.evaluate("webview-eval")
        _ = try engine.evaluate("webview-on-message")
        _ = try engine.evaluate("webview-set-style!")
    }

    @Test func allFunctionsAreProcedures() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? webview-create)") == .true)
        #expect(try engine.evaluate("(procedure? webview-close)") == .true)
        #expect(try engine.evaluate("(procedure? webview-set-html!)") == .true)
        #expect(try engine.evaluate("(procedure? webview-eval)") == .true)
        #expect(try engine.evaluate("(procedure? webview-on-message)") == .true)
        #expect(try engine.evaluate("(procedure? webview-set-style!)") == .true)
    }

    // MARK: - webview-close with invalid id

    @Test func webviewCloseWithInvalidIdDoesNotThrow() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(webview-close \"nonexistent\")")
        #expect(result == .void)
    }

    // MARK: - webview-set-html! with invalid id

    @Test func webviewSetHtmlWithInvalidIdDoesNotThrow() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(webview-set-html! \"nonexistent\" \"<p>test</p>\")")
        #expect(result == .void)
    }

    // MARK: - webview-set-style! with invalid id

    @Test func webviewSetStyleWithInvalidIdDoesNotThrow() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(webview-set-style! \"nonexistent\" \"body { color: red }\")")
        #expect(result == .void)
    }

    // Note: webview-create, webview-eval, and webview-on-message require a running
    // NSApplication with a GUI session. They are tested via manual integration testing.
    // The WebViewManager can be unit tested independently for panel management logic.
}
