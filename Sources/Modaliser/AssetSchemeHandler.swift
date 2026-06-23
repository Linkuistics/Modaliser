import Foundation
import WebKit

/// Serves bundle-relative resources to a WKWebView via a custom URL scheme.
///
/// The overlay/chooser inline their CSS into the page, so an @font-face
/// `url(...)` resolves against the document — and `loadHTMLString(_:baseURL:)`
/// with a `file://` base URL does NOT grant the WebKit content process read
/// access to file subresources (it fails with a network error). A custom
/// scheme handler sidesteps the file-origin sandbox entirely: WebKit calls
/// us to fetch `modaliser-asset:///fonts/…woff2`, and we read the bytes off
/// disk from a fixed root directory (`*scheme-directory*`, passed as the
/// webview-create 'asset-root option).
///
/// Used for the bundled IBM Plex fonts; general enough for any static asset
/// (svg/png/css) a future block needs.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {

    /// The URL scheme this handler answers. Custom (not a WebKit-special
    /// scheme like http/file), so registration is always permitted.
    static let scheme = "modaliser-asset"

    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let fileURL = AssetSchemeHandler.resolvedFileURL(root: root, requestURL: url) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            // Missing/unreadable asset — surface as a resource-not-found so
            // the WebView simply falls back (e.g. to the next @font-face
            // family) instead of hanging.
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = AssetSchemeHandler.mimeType(forPathExtension: fileURL.pathExtension)
        let response = URLResponse(
            url: url, mimeType: mime,
            expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Reads complete synchronously in start(), so there is nothing in
        // flight to cancel.
    }

    // MARK: - Pure helpers (unit-tested without a WebView)

    /// Resolve a `modaliser-asset://…` request URL to a file under `root`.
    /// Returns nil for an empty path or any path that escapes `root`
    /// (path-traversal guard). Existence is checked by the caller.
    static func resolvedFileURL(root: URL, requestURL: URL) -> URL? {
        // Custom-scheme URLs look like modaliser-asset:///fonts/x.woff2 →
        // path "/fonts/x.woff2". Strip the leading slash to make it relative.
        var rel = requestURL.path
        while rel.hasPrefix("/") { rel.removeFirst() }
        guard !rel.isEmpty else { return nil }

        let rootStd = root.standardizedFileURL
        let candidate = rootStd.appendingPathComponent(rel).standardizedFileURL
        // Must stay within root — reject ../ escapes.
        let rootPrefix = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        guard candidate.path == rootStd.path || candidate.path.hasPrefix(rootPrefix) else {
            return nil
        }
        return candidate
    }

    /// MIME type for a file extension. Covers the asset kinds the WebView
    /// surfaces; defaults to application/octet-stream.
    static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "css": return "text/css"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }
}
