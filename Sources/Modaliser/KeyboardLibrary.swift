import CoreGraphics
import Foundation
import LispKit

/// Native LispKit library providing keyboard capture and hotkey registration.
/// Scheme name: (modaliser keyboard)
///
/// Provides: start-keyboard-capture!, stop-keyboard-capture!,
/// register-hotkey!, unregister-hotkey!, register-all-keys!, unregister-all-keys!,
/// keycode->char
///
/// Also exports key code constants (F17, F18, ESCAPE, etc.) and
/// modifier flag constants (MOD-CMD, MOD-SHIFT, MOD-ALT, MOD-CTRL).
///
/// The registration-as-state pattern: modal state is expressed structurally.
/// When register-all-keys! is active, the app is modal. When it's removed, it's not.
final class KeyboardLibrary: NativeLibrary {

    let handlerRegistry = KeyboardHandlerRegistry()
    private var keyboardCapture: KeyboardCapture?

    // Static references to prevent GC from collecting capture/registry
    private static var sharedCapture: KeyboardCapture?
    private static var sharedRegistry: KeyboardHandlerRegistry?

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "keyboard"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        // Capture lifecycle
        self.define(Procedure("start-keyboard-capture!", startCaptureFunction))
        self.define(Procedure("stop-keyboard-capture!", stopCaptureFunction))

        // Handler registration
        self.define(Procedure("register-hotkey!", registerHotkeyFunction))
        self.define(Procedure("unregister-hotkey!", unregisterHotkeyFunction))
        self.define(Procedure("register-all-keys!", registerAllKeysFunction))
        self.define(Procedure("unregister-all-keys!", unregisterAllKeysFunction))

        // Key mapping
        self.define(Procedure("keycode->char", keycodeToCharFunction))

        // Key code constants
        self.define("F17", as: .fixnum(Int64(KeyCode.f17)))
        self.define("F18", as: .fixnum(Int64(KeyCode.f18)))
        self.define("F19", as: .fixnum(Int64(KeyCode.f19)))
        self.define("F20", as: .fixnum(Int64(KeyCode.f20)))
        self.define("ESCAPE", as: .fixnum(Int64(KeyCode.escape)))
        self.define("DELETE", as: .fixnum(Int64(KeyCode.delete)))
        self.define("RETURN", as: .fixnum(Int64(KeyCode.returnKey)))
        self.define("TAB", as: .fixnum(Int64(KeyCode.tab)))
        self.define("SPACE", as: .fixnum(Int64(KeyCode.space)))

        // Arrow keys
        self.define("UP", as: .fixnum(Int64(126)))
        self.define("DOWN", as: .fixnum(Int64(125)))
        self.define("LEFT", as: .fixnum(Int64(123)))
        self.define("RIGHT", as: .fixnum(Int64(124)))

        // Modifier flag constants (CGEventFlags raw values, shifted to usable bit positions)
        self.define("MOD-CMD", as: .fixnum(Int64(CGEventFlags.maskCommand.rawValue)))
        self.define("MOD-SHIFT", as: .fixnum(Int64(CGEventFlags.maskShift.rawValue)))
        self.define("MOD-ALT", as: .fixnum(Int64(CGEventFlags.maskAlternate.rawValue)))
        self.define("MOD-CTRL", as: .fixnum(Int64(CGEventFlags.maskControl.rawValue)))
    }

    // MARK: - Capture lifecycle

    /// (start-keyboard-capture!) → void
    private func startCaptureFunction() throws -> Expr {
        guard keyboardCapture == nil else { return .void }

        let registry = self.handlerRegistry
        let capture = KeyboardCapture { event in
            guard event.isKeyDown else { return .passThrough }
            let result = registry.dispatch(
                keyCode: event.keyCode,
                modifiers: event.modifiers
            )
            return result == .suppress ? .suppress : .passThrough
        }
        try capture.start()
        keyboardCapture = capture
        // Also store globally to prevent GC from collecting the library
        KeyboardLibrary.sharedCapture = capture
        KeyboardLibrary.sharedRegistry = registry
        NSLog("KeyboardLibrary: capture started")
        return .void
    }

    /// (stop-keyboard-capture!) → void
    private func stopCaptureFunction() -> Expr {
        keyboardCapture?.stop()
        keyboardCapture = nil
        NSLog("KeyboardLibrary: capture stopped")
        return .void
    }

    // MARK: - Hotkey registration

    /// (register-hotkey! keycode handler) → void
    private func registerHotkeyFunction(_ keycodeExpr: Expr, _ handler: Expr) throws -> Expr {
        let keyCode = CGKeyCode(try keycodeExpr.asInt64())
        guard case .procedure = handler else {
            throw RuntimeError.type(handler, expected: [.procedureType])
        }
        let evaluator = self.context.evaluator!
        handlerRegistry.hotkeyHandlers[keyCode] = {
            let result = evaluator.execute { machine in
                try machine.apply(handler, to: .null)
            }
            if case .error(let err) = result {
                NSLog("KeyboardLibrary: hotkey handler error: %@", "\(err)")
            }
        }
        return .void
    }

    /// (unregister-hotkey! keycode) → void
    private func unregisterHotkeyFunction(_ keycodeExpr: Expr) throws -> Expr {
        let keyCode = CGKeyCode(try keycodeExpr.asInt64())
        handlerRegistry.hotkeyHandlers.removeValue(forKey: keyCode)
        return .void
    }

    // MARK: - Catch-all registration

    /// (register-all-keys! handler) → void
    /// handler: (lambda (keycode modifiers) ...) → #t to suppress, #f to pass
    private func registerAllKeysFunction(_ handler: Expr) throws -> Expr {
        guard case .procedure = handler else {
            throw RuntimeError.type(handler, expected: [.procedureType])
        }
        let evaluator = self.context.evaluator!
        let registry = self.handlerRegistry
        handlerRegistry.catchAllHandler = { keyCode, modifiers in
            let args: Expr = .pair(
                .fixnum(Int64(keyCode)),
                .pair(.fixnum(Int64(modifiers.rawValue)), .null)
            )
            let result = evaluator.execute { machine in
                try machine.apply(handler, to: args)
            }
            switch result {
            case .true:
                return true
            case .error(let err):
                NSLog("KeyboardLibrary: catch-all handler error: %@", "\(err)")
                // Safety: deregister catch-all on error to prevent stuck modal
                registry.catchAllHandler = nil
                NSLog("KeyboardLibrary: catch-all deregistered after error (safety recovery)")
                return false
            default:
                return false
            }
        }
        return .void
    }

    /// (unregister-all-keys!) → void
    private func unregisterAllKeysFunction() -> Expr {
        handlerRegistry.catchAllHandler = nil
        return .void
    }

    // MARK: - Key mapping

    /// (keycode->char keycode) → string or #f
    private func keycodeToCharFunction(_ keycodeExpr: Expr) throws -> Expr {
        let keyCode = CGKeyCode(try keycodeExpr.asInt64())
        if let char = KeyboardLibrary.keyCodeToCharacter[keyCode] {
            return .makeString(char)
        }
        return .false
    }

    /// US ANSI keyboard layout mapping. HID key codes are physical positions,
    /// not characters — so key code 0 is the "A" position regardless of layout.
    private static let keyCodeToCharacter: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
        6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k",
        45: "n", 46: "m",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[",
        39: "'", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`",
        49: " ",
    ]
}
