import AppKit
import WebKit

/// Manages WKWebView-backed NSPanels for the WebView primitive library.
/// Each panel is identified by a string id and can be configured as
/// activating (takes keyboard focus) or non-activating (floating overlay).
final class WebViewManager: NSObject, WKScriptMessageHandler {

    private var panels: [String: NSPanel] = [:]
    private var webViews: [String: WKWebView] = [:]
    private var messageHandlers: [String: (Any) -> Void] = [:]

    /// Create a WebView-backed panel with the given options.
    func createPanel(
        id: String,
        width: CGFloat = 300,
        height: CGFloat = 400,
        x: CGFloat? = nil,
        y: CGFloat? = nil,
        activating: Bool = false,
        floating: Bool = true,
        transparent: Bool = false,
        shadow: Bool = true
    ) {
        // Close existing panel with same id
        closePanel(id: id)

        var styleMask: NSWindow.StyleMask = [.borderless]
        if !activating {
            styleMask.insert(.nonactivatingPanel)
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.level = floating ? .floating : .normal
        panel.isOpaque = false
        panel.backgroundColor = transparent ? .clear : .windowBackgroundColor
        panel.hasShadow = shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "modaliser")
        if transparent {
            config.setValue(false, forKey: "_drawsBackground")
        }

        let webView = WKWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        if transparent {
            webView.setValue(false, forKey: "drawsBackground")
        }
        panel.contentView?.addSubview(webView)

        // Position
        if let x, let y {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let px = sf.midX - width / 2
            let py = sf.maxY - (sf.height * 0.2) - height
            panel.setFrameOrigin(NSPoint(x: px, y: py))
        }

        panel.orderFront(nil)
        panels[id] = panel
        webViews[id] = webView
    }

    /// Close and destroy a panel.
    func closePanel(id: String) {
        if let webView = webViews[id] {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "modaliser")
        }
        panels[id]?.orderOut(nil)
        panels[id]?.close()
        panels.removeValue(forKey: id)
        webViews.removeValue(forKey: id)
        messageHandlers.removeValue(forKey: id)
    }

    /// Set the full HTML content of a panel's WebView.
    func setHTML(id: String, html: String) {
        webViews[id]?.loadHTMLString(html, baseURL: nil)
    }

    /// Evaluate JavaScript in a panel's WebView.
    func evaluateJavaScript(id: String, script: String, completion: ((String?) -> Void)? = nil) {
        guard let webView = webViews[id] else {
            completion?(nil)
            return
        }
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                NSLog("WebViewManager: JS eval error: %@", "\(error)")
                completion?(nil)
            } else if let result {
                completion?("\(result)")
            } else {
                completion?(nil)
            }
        }
    }

    /// Register a message handler for a panel.
    func setMessageHandler(id: String, handler: @escaping (Any) -> Void) {
        messageHandlers[id] = handler
    }

    /// Inject or replace a dynamic style block.
    func setStyle(id: String, css: String) {
        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = """
            (function() {
                var s = document.getElementById('dynamic-style');
                if (!s) { s = document.createElement('style'); s.id = 'dynamic-style'; document.head.appendChild(s); }
                s.textContent = '\(escapedCSS)';
            })();
            """
        webViews[id]?.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Find which panel this message came from
        for (id, webView) in webViews {
            if webView.configuration.userContentController === userContentController {
                messageHandlers[id]?(message.body)
                return
            }
        }
    }
}
