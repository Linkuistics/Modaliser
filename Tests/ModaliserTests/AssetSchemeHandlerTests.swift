import Testing
import Foundation
@testable import Modaliser

@Suite("Asset Scheme Handler")
struct AssetSchemeHandlerTests {

    private let root = URL(fileURLWithPath: "/tmp/modaliser-assets", isDirectory: true)

    private func request(_ s: String) -> URL {
        URL(string: s)!
    }

    // MARK: - resolvedFileURL

    @Test func resolvesAssetUnderRoot() {
        let resolved = AssetSchemeHandler.resolvedFileURL(
            root: root,
            requestURL: request("modaliser-asset:///fonts/ibm-plex-sans-latin-400-normal.woff2"))
        #expect(resolved?.path == "/tmp/modaliser-assets/fonts/ibm-plex-sans-latin-400-normal.woff2")
    }

    @Test func resolvesNestedSubdirectory() {
        let resolved = AssetSchemeHandler.resolvedFileURL(
            root: root, requestURL: request("modaliser-asset:///a/b/c.svg"))
        #expect(resolved?.path == "/tmp/modaliser-assets/a/b/c.svg")
    }

    @Test func rejectsParentTraversalEscape() {
        // ../ that climbs out of the root must be refused, not served.
        let resolved = AssetSchemeHandler.resolvedFileURL(
            root: root, requestURL: request("modaliser-asset:///../secrets.txt"))
        #expect(resolved == nil)
    }

    @Test func rejectsEmptyPath() {
        let resolved = AssetSchemeHandler.resolvedFileURL(
            root: root, requestURL: request("modaliser-asset:///"))
        #expect(resolved == nil)
    }

    @Test func interiorDotDotThatStaysInRootIsAllowed() {
        // fonts/../fonts/x.woff2 normalises back under root → permitted.
        let resolved = AssetSchemeHandler.resolvedFileURL(
            root: root, requestURL: request("modaliser-asset:///fonts/../fonts/x.woff2"))
        #expect(resolved?.path == "/tmp/modaliser-assets/fonts/x.woff2")
    }

    // MARK: - mimeType

    @Test func mimeTypeForFonts() {
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "woff2") == "font/woff2")
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "WOFF2") == "font/woff2")
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "ttf") == "font/ttf")
    }

    @Test func mimeTypeForWebAssets() {
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "css") == "text/css")
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "js") == "text/javascript")
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "svg") == "image/svg+xml")
    }

    @Test func mimeTypeDefaultsToOctetStream() {
        #expect(AssetSchemeHandler.mimeType(forPathExtension: "xyz") == "application/octet-stream")
    }

    // MARK: - scheme constant

    @Test func schemeIsCustomAndStable() {
        #expect(AssetSchemeHandler.scheme == "modaliser-asset")
    }
}
