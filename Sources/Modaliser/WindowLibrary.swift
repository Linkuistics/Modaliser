import AppKit
import LispKit

/// Native LispKit library providing window management.
/// Scheme name: (modaliser window)
///
/// Provides: list-windows, focus-window, center-window, move-window,
///           toggle-fullscreen, restore-window
final class WindowLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "window"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define", "assoc", "cdr")
    }

    public override func declarations() {
        self.define(Procedure("list-windows", listWindowsFunction))
        self.define(Procedure("focus-window", focusWindowFunction))
        self.define(Procedure("center-window", centerWindowFunction))
        self.define(Procedure("move-window", moveWindowFunction))
        self.define(Procedure("toggle-fullscreen", toggleFullscreenFunction))
        self.define(Procedure("restore-window", restoreWindowFunction))
    }

    // MARK: - Functions

    /// (list-windows) → list of alists
    /// Each entry: text (title), subText (app name), icon (bundleId), iconType, windowId, ownerPid
    private func listWindowsFunction() -> Expr {
        let windows = WindowEnumerator.listVisibleWindows()
        var result: Expr = .null
        for window in windows.reversed() {
            let alist = makeWindowAlist(window)
            result = .pair(alist, result)
        }
        return result
    }

    /// (focus-window choice-alist) → void
    private func focusWindowFunction(_ choice: Expr) throws -> Expr {
        guard let pid = SchemeAlistLookup.lookupFixnum(choice, key: "ownerPid"),
              let title = SchemeAlistLookup.lookupString(choice, key: "text") else {
            return .void
        }
        WindowManipulator.focusWindow(ownerPID: pid_t(pid), title: title)
        return .void
    }

    /// (center-window) → void
    private func centerWindowFunction() -> Expr {
        WindowManipulator.centerFocusedWindow()
        return .void
    }

    /// (move-window x y width height) → void
    /// All arguments are unit fractions (0.0-1.0) of the screen.
    private func moveWindowFunction(_ xExpr: Expr, _ yExpr: Expr,
                                     _ wExpr: Expr, _ hExpr: Expr) throws -> Expr {
        let x = try xExpr.asDouble(coerce: true)
        let y = try yExpr.asDouble(coerce: true)
        let w = try wExpr.asDouble(coerce: true)
        let h = try hExpr.asDouble(coerce: true)
        WindowManipulator.moveFocusedWindow(x: x, y: y, width: w, height: h)
        return .void
    }

    /// (toggle-fullscreen) → void
    private func toggleFullscreenFunction() -> Expr {
        WindowManipulator.toggleFullscreen()
        return .void
    }

    /// (restore-window) → void
    private func restoreWindowFunction() -> Expr {
        WindowManipulator.restoreFocusedWindow()
        return .void
    }

    // MARK: - Helpers

    private func makeWindowAlist(_ window: WindowInfo) -> Expr {
        SchemeAlistLookup.makeAlist([
            ("text", .makeString(window.title)),
            ("subText", .makeString(window.ownerName)),
            ("icon", .makeString(window.bundleId)),
            ("iconType", .makeString("bundleId")),
            ("windowId", .fixnum(Int64(window.windowId))),
            ("ownerPid", .fixnum(Int64(window.ownerPID))),
        ], symbols: self.context.symbols)
    }
}
