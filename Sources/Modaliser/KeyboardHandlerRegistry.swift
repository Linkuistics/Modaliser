import AppKit
import CoreGraphics

/// Stores registered keyboard handlers and dispatches key events to them.
/// Separates the dispatch logic from the CGEvent tap and the Scheme bridge,
/// making it independently testable.
///
/// Dispatch priority:
/// 1. Capture buffer (if active) — buffers the event, returns suppress.
/// 2. Armed-passthrough state — the leader hit over an arm-bundle app started
///    a brief window where the next press of the same leader cancels the
///    remote and enters the local modal. Synchronous, runs entirely in this
///    file so timing is deterministic.
/// 3. Catch-all handler (modal mode) — receives all keys.
/// 4. Specific hotkey handler:
///    - If frontmost app is in armBundleIds: enter armed state, pass the
///      trigger through to the window. The handler does NOT fire yet —
///      it fires only on the second trigger within the arm window.
///    - Otherwise: fire handler, return suppress.
/// 5. Pass through.
final class KeyboardHandlerRegistry {

    /// Handler for all keys (used during modal mode).
    /// Receives (keyCode, modifiers). Returns true to suppress, false to pass through.
    var catchAllHandler: ((_ keyCode: CGKeyCode, _ modifiers: CGEventFlags) -> Bool)?

    /// Handlers for specific (keycode, modifiers) combinations.
    var hotkeyHandlers: [HotkeyKey: HotkeyEntry] = [:]

    /// Active capture buffer, set when a hotkey handler is mid-flight to
    /// prevent its (asynchronously-running) Scheme handler from racing the
    /// next keystroke. Either drained through the resulting catch-all (if
    /// the handler installed one) or re-injected (if it didn't).
    var captureBuffer: CaptureBuffer?

    /// Frontmost-app bundle ID lookup. Injectable for tests.
    var frontmostBundleId: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Arm window — how long after a trigger over an arm-bundle app the
    /// second trigger counts as "cancel remote and enter local modal".
    /// Configured from Scheme via (set-arm-delay! seconds).
    var armWindow: TimeInterval = 0.5

    /// How to send the cancellation Escape to the focused window when the
    /// second trigger fires. The default posts a magic-tagged synthetic
    /// CGEvent so our own tap passes it through to the window. Tests inject
    /// a no-op or recording closure to avoid actually pressing Escape on the
    /// runner machine.
    var postEscapeKeystroke: () -> Void = KeyboardHandlerRegistry.defaultPostEscape

    /// Current arm state. Read-only outside the registry; mutated only via
    /// dispatch and the timer callback.
    private(set) var armState: ArmState = .idle
    private var armedHandler: (() -> Void)?
    private var armTimer: DispatchSourceTimer?

    /// Dispatch a key event. Returns whether to suppress or pass through.
    func dispatch(keyCode: CGKeyCode, modifiers: CGEventFlags, isKeyDown: Bool) -> KeyboardDispatchResult {
        if let buffer = captureBuffer {
            buffer.events.append(
                BufferedKeyEvent(keyCode: keyCode, modifiers: modifiers, isKeyDown: isKeyDown))
            return .suppress
        }

        // Armed state takes precedence over both catch-all and hotkey
        // lookups: the user is in a transient "double-tap" window and any
        // key resolves it. Key-up events pass through unchanged so the
        // window doesn't see stuck modifiers.
        if case .armed(let leaderKey) = armState, isKeyDown {
            let normalized = HotkeyKey(
                keyCode: keyCode,
                modifiers: modifiers.intersection(KeyboardHandlerRegistry.primaryModifiers))
            if normalized == leaderKey {
                let handler = armedHandler
                disarm()
                postEscapeKeystroke()
                handler?()
                return .suppress
            }
            // Any other key: cancel the arm and let the key flow naturally.
            disarm()
            return .passThrough
        }

        // Catch-all and hotkey handlers only fire on key-down — key-up just
        // passes through so the focused app gets a clean release event for
        // any modifier that was held when modal began.
        guard isKeyDown else { return .passThrough }

        if let catchAll = catchAllHandler {
            let shouldSuppress = catchAll(keyCode, modifiers)
            return shouldSuppress ? .suppress : .passThrough
        }

        if let entry = findEntry(keyCode: keyCode, modifiers: modifiers) {
            if !entry.armBundleIds.isEmpty,
               let bundleId = frontmostBundleId(),
               entry.armBundleIds.contains(bundleId)
            {
                let normalized = HotkeyKey(
                    keyCode: keyCode,
                    modifiers: modifiers.intersection(KeyboardHandlerRegistry.primaryModifiers))
                arm(leaderKey: normalized, handler: entry.handler)
                return .passThrough
            }
            entry.handler()
            return .suppress
        }

        return .passThrough
    }

    /// Enter the armed state. Cancels any in-flight arm timer (re-arm after
    /// a stray trigger restarts the window). Visible to tests so they can
    /// drive the state machine without real CGEvent dispatch.
    func arm(leaderKey: HotkeyKey, handler: @escaping () -> Void) {
        armTimer?.cancel()
        armState = .armed(leaderKey: leaderKey)
        armedHandler = handler
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + armWindow)
        timer.setEventHandler { [weak self] in
            self?.disarm()
        }
        armTimer = timer
        timer.resume()
    }

    /// Return to idle. Idempotent.
    func disarm() {
        armTimer?.cancel()
        armTimer = nil
        armState = .idle
        armedHandler = nil
    }

    /// Exact-key lookup. Modifiers are normalized to the four primary bits
    /// (cmd/shift/alt/ctrl) before lookup, so Caps Lock and friends don't
    /// affect matching.
    private func findEntry(keyCode: CGKeyCode, modifiers: CGEventFlags) -> HotkeyEntry? {
        let normalized = modifiers.intersection(KeyboardHandlerRegistry.primaryModifiers)
        return hotkeyHandlers[HotkeyKey(keyCode: keyCode, modifiers: normalized)]
    }

    /// Production Escape post: synthesise a magic-tagged keyDown+keyUp pair
    /// so our own tap recognises and passes them through to the window.
    private static func defaultPostEscape() {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil,
                                      virtualKey: CGKeyCode(KeyCode.escape),
                                      keyDown: keyDown)
            else { continue }
            event.setIntegerValueField(.eventSourceUserData,
                                       value: KeyboardCapture.reInjectionMagic)
            event.post(tap: .cgSessionEventTap)
        }
    }

    static let primaryModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]
}

/// Composite key for hotkey lookup: a keycode plus a normalized modifier mask.
/// Modifiers are restricted to [.maskShift, .maskControl, .maskAlternate, .maskCommand]
/// (Caps Lock, function-key, numpad bits are stripped before lookup).
struct HotkeyKey: Hashable {
    let keyCode: CGKeyCode
    /// Stored as raw value because CGEventFlags isn't Hashable directly.
    let modifiers: UInt64

    init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }
}

/// A registered hotkey: handler plus arm rule.
struct HotkeyEntry {
    let handler: () -> Void
    /// Bundle IDs of frontmost apps where this hotkey uses pass-and-arm:
    /// the trigger is passed through to the window and the registry enters
    /// the armed state. Empty list means always capture.
    let armBundleIds: [String]
}

/// Two-state machine for the pass-and-arm leader. The leader key is stored
/// so we know which keycode counts as the second trigger.
enum ArmState: Equatable {
    case idle
    case armed(leaderKey: HotkeyKey)
}

/// Result of keyboard dispatch — tells the CGEvent tap what to do.
enum KeyboardDispatchResult {
    case suppress
    case passThrough
}

/// A key event captured by the optimistic-capture buffer. Stores enough to
/// either feed back through a catch-all handler or synthesise a fresh CGEvent
/// for re-injection.
struct BufferedKeyEvent {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let isKeyDown: Bool
}

/// Reference type so the entry.handler closure and the async finalizer
/// share the same buffer instance (and so the registry's `captureBuffer`
/// reference can be compared by identity if needed).
final class CaptureBuffer {
    var events: [BufferedKeyEvent] = []
}
