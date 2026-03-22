import Foundation
import LispKit

/// Native LispKit library providing WKWebView-backed window management.
/// Scheme name: (modaliser webview)
///
/// Provides: webview-create, webview-close, webview-set-html!, webview-eval,
/// webview-on-message, webview-set-style!
///
/// Each WebView is an NSPanel identified by a string id. Panels can be
/// non-activating (floating overlays) or activating (takes keyboard focus
/// for text input like the chooser search field).
final class WebViewLibrary: NativeLibrary {

    let webViewManager = WebViewManager()

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "webview"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("webview-create", webviewCreateFunction))
        self.define(Procedure("webview-close", webviewCloseFunction))
        self.define(Procedure("webview-set-html!", webviewSetHtmlFunction))
        self.define(Procedure("webview-eval", webviewEvalFunction))
        self.define(Procedure("webview-on-message", webviewOnMessageFunction))
        self.define(Procedure("webview-set-style!", webviewSetStyleFunction))
    }

    // MARK: - Primitives

    /// (webview-create id options-alist) → id
    private func webviewCreateFunction(_ idExpr: Expr, _ options: Expr) throws -> Expr {
        let id = try idExpr.asString()

        let width = SchemeAlistLookup.lookupFixnum(options, key: "width").map { CGFloat($0) } ?? 300
        let height = SchemeAlistLookup.lookupFixnum(options, key: "height").map { CGFloat($0) } ?? 400
        let x = SchemeAlistLookup.lookupFixnum(options, key: "x").map { CGFloat($0) }
        let y = SchemeAlistLookup.lookupFixnum(options, key: "y").map { CGFloat($0) }
        let activating = lookupBool(options, key: "activating") ?? false
        let floating = lookupBool(options, key: "floating") ?? true
        let transparent = lookupBool(options, key: "transparent") ?? false
        let shadow = lookupBool(options, key: "shadow") ?? true

        webViewManager.createPanel(
            id: id,
            width: width,
            height: height,
            x: x,
            y: y,
            activating: activating,
            floating: floating,
            transparent: transparent,
            shadow: shadow
        )

        return .makeString(id)
    }

    /// (webview-close id) → void
    private func webviewCloseFunction(_ idExpr: Expr) throws -> Expr {
        let id = try idExpr.asString()
        webViewManager.closePanel(id: id)
        return .void
    }

    /// (webview-set-html! id html-string) → void
    private func webviewSetHtmlFunction(_ idExpr: Expr, _ html: Expr) throws -> Expr {
        let id = try idExpr.asString()
        let htmlStr = try html.asString()
        webViewManager.setHTML(id: id, html: htmlStr)
        return .void
    }

    /// (webview-eval id js-string) → string or void
    private func webviewEvalFunction(_ idExpr: Expr, _ js: Expr) throws -> Expr {
        let id = try idExpr.asString()
        let jsStr = try js.asString()
        // Synchronous for now — evaluateJavaScript is async but we need to return a result.
        // For the common case (DOM manipulation), the result is not needed.
        // Return void; callers that need results should use webview-on-message instead.
        webViewManager.evaluateJavaScript(id: id, script: jsStr)
        return .void
    }

    /// (webview-on-message id handler) → void
    private func webviewOnMessageFunction(_ idExpr: Expr, _ handler: Expr) throws -> Expr {
        let id = try idExpr.asString()
        guard case .procedure = handler else {
            throw RuntimeError.type(handler, expected: [.procedureType])
        }

        let evaluator = self.context.evaluator!
        webViewManager.setMessageHandler(id: id) { [weak self] body in
            guard let self else { return }
            let schemeValue = self.jsValueToScheme(body)
            // Defer evaluation to the next run loop iteration so the WebView
            // can process pending keyboard events before we block the main thread
            // with fuzzy matching and HTML rendering.
            DispatchQueue.main.async {
                let args: Expr = .pair(schemeValue, .null)
                let result = evaluator.execute { machine in
                    try machine.apply(handler, to: args)
                }
                if case .error(let err) = result {
                    NSLog("WebViewLibrary: message handler error: %@", "\(err)")
                }
            }
        }

        return .void
    }

    /// (webview-set-style! id css-string) → void
    private func webviewSetStyleFunction(_ idExpr: Expr, _ css: Expr) throws -> Expr {
        let id = try idExpr.asString()
        let cssStr = try css.asString()
        webViewManager.setStyle(id: id, css: cssStr)
        return .void
    }

    // MARK: - Helpers

    private func lookupBool(_ alist: Expr, key: String) -> Bool? {
        guard let expr = SchemeAlistLookup.lookupExpr(alist, key: key) else { return nil }
        return expr == .true
    }

    /// Convert a JavaScript value (from WKScriptMessage.body) to a Scheme expression.
    private func jsValueToScheme(_ value: Any) -> Expr {
        switch value {
        case let str as String:
            return .makeString(str)
        case let num as Int:
            return .fixnum(Int64(num))
        case let num as Double:
            return .flonum(num)
        case let bool as Bool:
            return bool ? .true : .false
        case let dict as [String: Any]:
            // Convert to alist
            var result: Expr = .null
            for (k, v) in dict {
                let pair = Expr.pair(.symbol(self.context.symbols.intern(k)), jsValueToScheme(v))
                result = .pair(pair, result)
            }
            return result
        case let arr as [Any]:
            // Convert to list
            var result: Expr = .null
            for item in arr.reversed() {
                result = .pair(jsValueToScheme(item), result)
            }
            return result
        default:
            return .makeString("\(value)")
        }
    }
}
