import AppKit
import LispKit

/// Native LispKit library providing clipboard access.
/// Scheme name: (modaliser pasteboard)
///
/// Provides: get-clipboard, set-clipboard!
final class PasteboardLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "pasteboard"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("get-clipboard", getClipboardFunction))
        self.define(Procedure("set-clipboard!", setClipboardFunction))
    }

    // MARK: - Functions

    /// (get-clipboard) → string
    private func getClipboardFunction() -> Expr {
        let contents = NSPasteboard.general.string(forType: .string) ?? ""
        return .makeString(contents)
    }

    /// (set-clipboard! text) → void
    private func setClipboardFunction(_ text: Expr) throws -> Expr {
        let string = try text.asString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        return .void
    }
}
