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
            // Both keyDown and keyUp go to dispatch — the registry decides
            // what to do based on isKeyDown. The buffer needs key-up too so
            // we can drain or re-inject without leaving keys "stuck down"
            // in the focused app.
            let result = registry.dispatch(
                keyCode: event.keyCode,
                modifiers: event.modifiers,
                isKeyDown: event.isKeyDown
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

    /// (register-hotkey! keycode handler [modifier-mask [passthrough-bundle-ids]]) → void
    /// modifier-mask defaults to 0 (no modifiers).
    /// passthrough-bundle-ids defaults to '() (always capture).
    ///
    /// Optimistic capture pattern. When the hotkey fires:
    ///   1. Synchronously install a capture buffer in the tap callback (just
    ///      sets a property, microseconds). Subsequent key events queue into
    ///      the buffer instead of leaking to the focused app.
    ///   2. Yield the tap callback so the kernel doesn't disable us by
    ///      timeout — Scheme leader handlers can shell out to osascript /
    ///      ps / lsof when probing iTerm panes, which can easily exceed the
    ///      tap's 1-second budget.
    ///   3. Dispatch the Scheme handler asynchronously on the main run loop.
    ///   4. After the Scheme handler returns, finalise:
    ///      - If a catch-all was installed (modal-enter fired): drain the
    ///        buffered events through it so they reach modal-key-handler in
    ///        arrival order.
    ///      - Otherwise (modal didn't enter — e.g. no app-local tree found):
    ///        re-inject the buffered events back into the system tap with a
    ///        magic eventSourceUserData so our own tap recognises them and
    ///        passes them through instead of re-buffering.
    private func registerHotkeyFunction(_ args: Arguments) throws -> Expr {
        guard args.count >= 2, args.count <= 4 else {
            throw RuntimeError.argumentCount(min: 2, max: 4, args: .makeList(args))
        }
        let argList = Array(args)
        let keyCode = CGKeyCode(try argList[0].asInt64())
        let handler = argList[1]
        guard case .procedure = handler else {
            throw RuntimeError.type(handler, expected: [.procedureType])
        }
        let modifierMask: UInt64 =
            argList.count >= 3 ? UInt64(try argList[2].asInt64()) : 0
        let passthrough: [String] =
            argList.count >= 4 ? try schemeListToStrings(argList[3]) : []

        let normalizedFlags = CGEventFlags(rawValue: modifierMask)
            .intersection(KeyboardHandlerRegistry.primaryModifiers)

        let evaluator = self.context.evaluator!
        let registry = self.handlerRegistry
        let key = HotkeyKey(keyCode: keyCode, modifiers: normalizedFlags)
        let entry = HotkeyEntry(
            handler: { [weak self] in
                self?.fireHotkeyHandler(handler, evaluator: evaluator, registry: registry)
            },
            passthroughBundleIds: passthrough
        )
        handlerRegistry.hotkeyHandlers[key] = entry
        return .void
    }

    /// Optimistic-capture finalize step. Called after the Scheme handler
    /// returns: drain through the new catch-all or re-inject events that
    /// the handler turned out not to want.
    private func fireHotkeyHandler(_ handler: Expr,
                                    evaluator: Evaluator,
                                    registry: KeyboardHandlerRegistry) {
        // Step 1: install the buffer synchronously. After this returns the
        // tap callback finishes; subsequent key events queue here.
        let buffer = CaptureBuffer()
        registry.captureBuffer = buffer

        // Step 2: dispatch Scheme work asynchronously. This yields the tap
        // callback immediately — even if Scheme spends seconds shelling out
        // to AppleScript probes, the kernel never disables our tap.
        DispatchQueue.main.async { [weak self] in
            let result = evaluator.execute { machine in
                try machine.apply(handler, to: .null)
            }
            if case .error(let err) = result {
                NSLog("KeyboardLibrary: hotkey handler error: %@", "\(err)")
            }
            self?.finalizeCapture(buffer: buffer, registry: registry)
        }
    }

    /// Drain the buffered events into the now-installed catch-all, or
    /// re-inject them if the leader handler didn't take ownership.
    private func finalizeCapture(buffer: CaptureBuffer,
                                  registry: KeyboardHandlerRegistry) {
        // Only finalize if we're still the active buffer — a nested leader
        // press could have replaced us with its own buffer in between.
        guard registry.captureBuffer === buffer else { return }
        registry.captureBuffer = nil

        if let catchAll = registry.catchAllHandler {
            // Modal active — feed events through in arrival order so the
            // user sees deterministic dispatch regardless of how slow the
            // Scheme handler was.
            for buffered in buffer.events {
                if buffered.isKeyDown {
                    _ = catchAll(buffered.keyCode, buffered.modifiers)
                }
            }
        } else {
            // Modal didn't enter — re-inject so the focused app sees the
            // keys it would have if our tap weren't here.
            for buffered in buffer.events {
                postSyntheticKeyEvent(buffered)
            }
        }
    }

    /// Synthesize and post a CGEvent matching a buffered key press. The
    /// event is tagged with KeyboardCapture.reInjectionMagic so our own tap
    /// recognises it and passes it through. Uses .cgSessionEventTap so the
    /// re-injected event flows through the same path as the original.
    private func postSyntheticKeyEvent(_ buffered: BufferedKeyEvent) {
        guard let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: buffered.keyCode,
                                  keyDown: buffered.isKeyDown)
        else { return }
        event.flags = buffered.modifiers
        event.setIntegerValueField(.eventSourceUserData,
                                   value: KeyboardCapture.reInjectionMagic)
        event.post(tap: .cgSessionEventTap)
    }

    /// (unregister-hotkey! keycode [modifier-mask]) → void
    /// modifier-mask defaults to 0. Different modifier combinations are independent.
    private func unregisterHotkeyFunction(_ args: Arguments) throws -> Expr {
        guard args.count >= 1, args.count <= 2 else {
            throw RuntimeError.argumentCount(min: 1, max: 2, args: .makeList(args))
        }
        let argList = Array(args)
        let keyCode = CGKeyCode(try argList[0].asInt64())
        let modifierMask: UInt64 =
            argList.count >= 2 ? UInt64(try argList[1].asInt64()) : 0
        let normalizedFlags = CGEventFlags(rawValue: modifierMask)
            .intersection(KeyboardHandlerRegistry.primaryModifiers)
        handlerRegistry.hotkeyHandlers.removeValue(
            forKey: HotkeyKey(keyCode: keyCode, modifiers: normalizedFlags)
        )
        return .void
    }

    /// Walk a Scheme proper list of strings into a Swift `[String]`.
    private func schemeListToStrings(_ expr: Expr) throws -> [String] {
        var out: [String] = []
        var node = expr
        while case .pair(let head, let tail) = node {
            out.append(try head.asString())
            node = tail
        }
        return out
    }

    // MARK: - Catch-all registration

    /// (register-all-keys! handler) → void
    /// handler: (lambda (keycode modifiers) ...) → #t to suppress, #f to pass
    ///
    /// Evaluation is deferred to the next run loop iteration via DispatchQueue.main.async.
    /// The suppress/pass decision is made synchronously based on modifiers:
    /// Cmd+anything passes through, all other keys are suppressed. This matches
    /// modal-key-handler's behavior exactly. The deferred evaluation handles
    /// side effects (overlay updates, modal-exit) without deadlocking WKWebView.
    private func registerAllKeysFunction(_ handler: Expr) throws -> Expr {
        guard case .procedure = handler else {
            throw RuntimeError.type(handler, expected: [.procedureType])
        }
        let evaluator = self.context.evaluator!
        let registry = self.handlerRegistry
        handlerRegistry.catchAllHandler = { keyCode, modifiers in
            // Cmd+anything passes through without evaluation
            if modifiers.contains(.maskCommand) {
                return false
            }
            // All other keys: suppress immediately, evaluate asynchronously
            DispatchQueue.main.async {
                let args: Expr = .pair(
                    .fixnum(Int64(keyCode)),
                    .pair(.fixnum(Int64(modifiers.rawValue)), .null)
                )
                let result = evaluator.execute { machine in
                    try machine.apply(handler, to: args)
                }
                if case .error(let err) = result {
                    NSLog("KeyboardLibrary: catch-all handler error: %@", "\(err)")
                    // Safety: deregister catch-all on error to prevent stuck modal
                    registry.catchAllHandler = nil
                    NSLog("KeyboardLibrary: catch-all deregistered after error (safety recovery)")
                }
            }
            return true
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
