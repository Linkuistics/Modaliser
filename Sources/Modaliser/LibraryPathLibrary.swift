import Foundation
import LispKit

/// Native LispKit library exposing library-path extension.
/// Scheme name: (modaliser library-path)
///
/// Provides: prepend-library-path!
final class LibraryPathLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "library-path"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("prepend-library-path!", prependLibraryPath))
    }

    /// (prepend-library-path! path) → boolean
    /// Adds `path` to the front of LispKit's library search list.
    /// Returns #t if the path exists and was added; #f if the path
    /// is missing (silently skipped, matching LispKit's behaviour).
    private func prependLibraryPath(_ path: Expr) throws -> Expr {
        let raw = try path.asString()
        let expanded = NSString(string: raw).expandingTildeInPath
        let added = self.context.fileHandler.prependLibrarySearchPath(expanded)
        return .makeBoolean(added)
    }
}
