import CoreGraphics
import LispKit

/// Native LispKit library providing keyboard input emulation.
/// Scheme name: (modaliser input)
///
/// Provides: send-keystroke, send-key-down, send-key-up
final class InputLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "input"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("send-keystroke", sendKeystrokeFunction))
        self.define(Procedure("send-key-down", sendKeyDownFunction))
        self.define(Procedure("send-key-up", sendKeyUpFunction))
    }

    // MARK: - Functions

    /// (send-keystroke mods key) → void
    /// mods: list of modifier symbols ('cmd 'alt 'shift 'ctrl)
    /// key: string character ("t", "p", "left", "space", etc.)
    ///
    /// Examples:
    ///   (send-keystroke '(cmd) "t")            ; Cmd+T
    ///   (send-keystroke '(cmd shift) "p")       ; Cmd+Shift+P
    ///   (send-keystroke '(cmd alt) "left")      ; Cmd+Alt+Left
    ///   (send-keystroke '() "space")            ; Space
    private func sendKeystrokeFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
        let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
        KeystrokeEmitter.sendKeystroke(keyCode: keyCode, flags: flags)
        return .void
    }

    private func sendKeyDownFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
        let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
        KeystrokeEmitter.sendKeyDown(keyCode: keyCode, flags: flags)
        return .void
    }

    private func sendKeyUpFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
        let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
        KeystrokeEmitter.sendKeyUp(keyCode: keyCode, flags: flags)
        return .void
    }

    // MARK: - Helpers

    private func resolveKey(_ modsExpr: Expr, _ keyExpr: Expr) throws -> (CGKeyCode, CGEventFlags) {
        let keyString = try keyExpr.asString()
        let flags = parseModifiers(modsExpr)
        guard let keyCode = KeystrokeEmitter.keyCode(for: keyString)
                ?? KeystrokeEmitter.keyCode(forNamedKey: keyString) else {
            throw RuntimeError.custom("eval", "unknown key '\(keyString)'", [keyExpr])
        }
        return (keyCode, flags)
    }

    private func parseModifiers(_ expr: Expr) -> CGEventFlags {
        var flags: CGEventFlags = []
        var current = expr
        while case .pair(let head, let tail) = current {
            if case .symbol(let sym) = head {
                switch sym.identifier {
                case "cmd", "command": flags.insert(.maskCommand)
                case "alt", "option": flags.insert(.maskAlternate)
                case "shift": flags.insert(.maskShift)
                case "ctrl", "control": flags.insert(.maskControl)
                default: break
                }
            }
            current = tail
        }
        return flags
    }
}
