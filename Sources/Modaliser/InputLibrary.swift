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

    /// (send-keystroke [mods] key) → void
    /// mods: optional list of modifier symbols ('cmd 'alt 'shift 'ctrl).
    ///       Omit it entirely for no modifiers.
    /// key: string character ("t", "p", "left", "space", etc.)
    ///
    /// Examples:
    ///   (send-keystroke "tab")                  ; Tab (plus any held modifiers)
    ///   (send-keystroke '(cmd) "t")            ; Cmd+T
    ///   (send-keystroke '(cmd shift) "p")       ; Cmd+Shift+P
    private func sendKeystrokeFunction(_ args: Arguments) throws -> Expr {
        let (keyCode, flags) = try resolveArgs(args)
        KeystrokeEmitter.sendKeystroke(keyCode: keyCode, flags: flags)
        return .void
    }

    /// (send-key-down [mods] key) → void — see resolveArgs for the arity rule.
    private func sendKeyDownFunction(_ args: Arguments) throws -> Expr {
        let (keyCode, flags) = try resolveArgs(args)
        KeystrokeEmitter.sendKeyDown(keyCode: keyCode, flags: flags)
        return .void
    }

    /// (send-key-up [mods] key) → void — see resolveArgs for the arity rule.
    private func sendKeyUpFunction(_ args: Arguments) throws -> Expr {
        let (keyCode, flags) = try resolveArgs(args)
        KeystrokeEmitter.sendKeyUp(keyCode: keyCode, flags: flags)
        return .void
    }

    // MARK: - Helpers

    /// Resolve the (keyCode, flags) for the input procedures. Accepts either
    /// one argument (the key string, no modifiers) or two (modifier-symbol
    /// list, then key string).
    private func resolveArgs(_ args: Arguments) throws -> (CGKeyCode, CGEventFlags) {
        let argList = Array(args)
        let modsExpr: Expr
        let keyExpr: Expr
        switch argList.count {
        case 1: modsExpr = .null;        keyExpr = argList[0]
        case 2: modsExpr = argList[0];   keyExpr = argList[1]
        default:
            throw RuntimeError.argumentCount(min: 1, max: 2, args: .makeList(args))
        }
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
