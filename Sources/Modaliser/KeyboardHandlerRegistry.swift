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
///
/// ## Threading
///
/// `dispatch` runs on the dedicated event-tap thread (see `KeyboardCapture`),
/// whereas handler registration, the optimistic-capture finalizer, and the
/// arm-window timer all run on the main thread. Every access to the mutable
/// state below therefore goes through `lock`.
///
/// The lock is held only for the brief decision section of `dispatch` — never
/// across a call-out to a hotkey handler, the catch-all, or the Escape poster.
/// Those call-outs can shell out to slow AppleScript probes; holding the lock
/// across them would let a slow Scheme handler stall the tap thread, which is
/// exactly the failure this design avoids.
final class KeyboardHandlerRegistry {

    /// Serializes access to all mutable state below. Held for microseconds at
    /// a time; never held across a handler call-out.
    private let lock = NSLock()

    // MARK: - Shared state (guarded by `lock`)

    private var _catchAllHandler: ((CGKeyCode, CGEventFlags) -> Bool)?
    private var _hotkeyHandlers: [HotkeyKey: HotkeyEntry] = [:]
    private var _captureBuffer: CaptureBuffer?
    private var _armState: ArmState = .idle
    private var _armedHandler: (() -> Void)?
    private var _armTimer: DispatchSourceTimer?
    private var _armWindow: TimeInterval = 0.5
    private var _cachedFrontmostBundleId: String?

    // MARK: - Public accessors

    /// Handler for all keys (used during modal mode).
    /// Receives (keyCode, modifiers). Returns true to suppress, false to pass through.
    var catchAllHandler: ((_ keyCode: CGKeyCode, _ modifiers: CGEventFlags) -> Bool)? {
        get { lock.lock(); defer { lock.unlock() }; return _catchAllHandler }
        set { lock.lock(); defer { lock.unlock() }; _catchAllHandler = newValue }
    }

    /// Handlers for specific (keycode, modifiers) combinations.
    var hotkeyHandlers: [HotkeyKey: HotkeyEntry] {
        get { lock.lock(); defer { lock.unlock() }; return _hotkeyHandlers }
        set { lock.lock(); defer { lock.unlock() }; _hotkeyHandlers = newValue }
    }

    /// Frontmost-app bundle ID lookup. Injectable for tests. The production
    /// default reads a cache refreshed on the main thread by
    /// `startTrackingFrontmostApp` — it never touches AppKit from the tap
    /// thread, where `NSWorkspace` access would be unsupported.
    var frontmostBundleId: () -> String? = { nil }

    /// Arm window — how long after a trigger over an arm-bundle app the
    /// second trigger counts as "cancel remote and enter local modal".
    /// Configured from Scheme via (set-arm-delay! seconds).
    var armWindow: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _armWindow }
        set { lock.lock(); defer { lock.unlock() }; _armWindow = newValue }
    }

    /// How to send the cancellation Escape to the focused window when the
    /// second trigger fires. The default posts a magic-tagged synthetic
    /// CGEvent so our own tap passes it through to the window. Tests inject
    /// a no-op or recording closure to avoid actually pressing Escape on the
    /// runner machine.
    var postEscapeKeystroke: () -> Void = KeyboardHandlerRegistry.defaultPostEscape

    /// Current arm state. Read-only outside the registry; mutated only via
    /// dispatch and the timer callback.
    var armState: ArmState {
        lock.lock(); defer { lock.unlock() }
        return _armState
    }

    private var frontmostObserver: NSObjectProtocol?

    init() {
        frontmostBundleId = { [weak self] in
            guard let self else { return nil }
            self.lock.lock(); defer { self.lock.unlock() }
            return self._cachedFrontmostBundleId
        }
    }

    deinit {
        stopTrackingFrontmostApp()
    }

    // MARK: - Frontmost-app tracking

    /// Begin mirroring the frontmost application's bundle ID into a cache that
    /// `dispatch` can read from the tap thread without touching AppKit. Call
    /// once, on the main thread, after keyboard capture starts.
    func startTrackingFrontmostApp() {
        let workspace = NSWorkspace.shared
        let seed = workspace.frontmostApplication?.bundleIdentifier
        lock.lock(); _cachedFrontmostBundleId = seed; lock.unlock()

        guard frontmostObserver == nil else { return }
        frontmostObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            self.lock.lock(); self._cachedFrontmostBundleId = bundleId; self.lock.unlock()
        }
    }

    /// Stop mirroring the frontmost application. Idempotent.
    func stopTrackingFrontmostApp() {
        if let observer = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontmostObserver = nil
        }
    }

    // MARK: - Dispatch

    /// Dispatch a key event. Returns whether to suppress or pass through.
    /// Safe to call from any thread; runs on the event-tap thread in production.
    func dispatch(keyCode: CGKeyCode, modifiers: CGEventFlags, isKeyDown: Bool) -> KeyboardDispatchResult {
        let normalizedKey = HotkeyKey(
            keyCode: keyCode,
            modifiers: modifiers.intersection(KeyboardHandlerRegistry.primaryModifiers))

        lock.lock()

        // Optimistic-capture buffer active — a hotkey handler is mid-flight.
        // Queue the event (key-up included, so we can drain or re-inject
        // without leaving keys "stuck down" in the focused app) and suppress.
        if let buffer = _captureBuffer {
            buffer.events.append(
                BufferedKeyEvent(keyCode: keyCode, modifiers: modifiers, isKeyDown: isKeyDown))
            lock.unlock()
            return .suppress
        }

        // Armed state takes precedence over both catch-all and hotkey
        // lookups: the user is in a transient "double-tap" window and any
        // key resolves it. Key-up events pass through unchanged so the
        // window doesn't see stuck modifiers.
        if case .armed(let leaderKey) = _armState, isKeyDown {
            if normalizedKey == leaderKey {
                let handler = _armedHandler
                disarmLocked()
                lock.unlock()
                postEscapeKeystroke()
                handler?()
                return .suppress
            }
            // Any other key: cancel the arm and let the key flow naturally.
            disarmLocked()
            lock.unlock()
            return .passThrough
        }

        // Catch-all and hotkey handlers only fire on key-down — key-up just
        // passes through so the focused app gets a clean release event for
        // any modifier that was held when modal began.
        guard isKeyDown else {
            lock.unlock()
            return .passThrough
        }

        if let catchAll = _catchAllHandler {
            // Released before the call-out: the catch-all may evaluate Scheme.
            lock.unlock()
            return catchAll(keyCode, modifiers) ? .suppress : .passThrough
        }

        guard let entry = _hotkeyHandlers[normalizedKey] else {
            lock.unlock()
            return .passThrough
        }
        let armBundleIds = entry.armBundleIds
        let handler = entry.handler
        lock.unlock()

        // Pass-and-arm: over an arm-bundle app the trigger flows to the
        // window and we enter the armed state instead of firing now.
        if !armBundleIds.isEmpty,
           let bundleId = frontmostBundleId(),
           armBundleIds.contains(bundleId)
        {
            lock.lock()
            armLocked(leaderKey: normalizedKey, handler: handler)
            lock.unlock()
            return .passThrough
        }

        handler()
        return .suppress
    }

    // MARK: - Optimistic-capture buffer

    /// Install a fresh optimistic-capture buffer and return it. Until the
    /// buffer is drained, subsequent key events queue into it (suppressed)
    /// instead of leaking to the focused app or racing the in-flight handler.
    func beginCapture() -> CaptureBuffer {
        let buffer = CaptureBuffer()
        lock.lock(); _captureBuffer = buffer; lock.unlock()
        return buffer
    }

    /// If `buffer` is still the active capture buffer, detach it and return a
    /// snapshot of its queued events (taken under the lock, so the tap thread
    /// can no longer append to it). Returns nil if a newer leader press has
    /// already replaced it — in which case the newer buffer owns finalization.
    func takeBufferIfCurrent(_ buffer: CaptureBuffer) -> [BufferedKeyEvent]? {
        lock.lock(); defer { lock.unlock() }
        guard _captureBuffer === buffer else { return nil }
        _captureBuffer = nil
        return buffer.events
    }

    // MARK: - Arm state

    /// Enter the armed state. Cancels any in-flight arm timer (re-arm after
    /// a stray trigger restarts the window). Caller must hold `lock`.
    private func armLocked(leaderKey: HotkeyKey, handler: @escaping () -> Void) {
        _armTimer?.cancel()
        _armState = .armed(leaderKey: leaderKey)
        _armedHandler = handler
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + _armWindow)
        timer.setEventHandler { [weak self] in
            self?.disarm()
        }
        _armTimer = timer
        timer.resume()
    }

    /// Return to idle. Caller must hold `lock`.
    private func disarmLocked() {
        _armTimer?.cancel()
        _armTimer = nil
        _armState = .idle
        _armedHandler = nil
    }

    /// Return to idle. Idempotent. Safe to call from any thread — used by the
    /// arm-window timer (main queue) and by tests.
    func disarm() {
        lock.lock(); defer { lock.unlock() }
        disarmLocked()
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
enum KeyboardDispatchResult: Equatable {
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
/// share the same buffer instance (and so the registry's capture buffer
/// can be compared by identity in `takeBufferIfCurrent`).
final class CaptureBuffer {
    var events: [BufferedKeyEvent] = []
}
