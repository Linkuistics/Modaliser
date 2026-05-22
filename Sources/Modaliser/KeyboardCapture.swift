import AppKit
import CoreGraphics

/// Result of handling a key event — tells the caller whether to suppress or pass through.
enum KeyEventHandlingResult: Equatable {
    /// Suppress the event (don't let it reach other apps).
    case suppress
    /// Pass the event through to the system.
    case passThrough
}

/// Captures global keyboard events via a CGEvent tap.
/// Requires Accessibility permissions to function.
///
/// ## Why a dedicated thread
///
/// The tap's run-loop source runs on its own thread, not the main run loop.
/// A CGEvent tap whose run loop stops servicing events for ~1 second is
/// disabled by the kernel (`.tapDisabledByTimeout`), after which keystrokes
/// bypass the tap entirely until it is re-enabled.
///
/// Leader-key handling deliberately blocks the *main* thread: Scheme leader
/// handlers shell out to osascript / ps when probing iTerm panes, and a cold
/// AppleScript round-trip can take seconds. If the tap shared the main run
/// loop, that block would stall the tap and the kernel would disable it —
/// dropping any key the user pressed during the probe. Running the tap on its
/// own thread keeps it servicing events (into the optimistic-capture buffer)
/// regardless of what the main thread is doing.
final class KeyboardCapture {
    private var onKeyEvent: (CapturedKeyEvent) -> KeyEventHandlingResult
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The dedicated thread servicing the tap, and its run loop. The run loop
    /// is published by the thread itself and read by `stop()`; `runLoopReady`
    /// guarantees it is set before `start()` returns.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private let runLoopReady = DispatchSemaphore(value: 0)

    init(onKeyEvent: @escaping (CapturedKeyEvent) -> KeyEventHandlingResult) {
        self.onKeyEvent = onKeyEvent
    }

    /// Replace the event handler without restarting the event tap.
    /// Used during config reload to re-wire to a new dispatcher.
    func updateHandler(_ handler: @escaping (CapturedKeyEvent) -> KeyEventHandlingResult) {
        self.onKeyEvent = handler
    }

    /// Start capturing keyboard events. Throws if Accessibility is not granted.
    func start() throws {
        // The Scheme-level (ensure-permissions! ...) gate runs before keyboard capture,
        // so by the time we get here AX should be granted. This is a defensive check —
        // if the user revoked AX between the gate and now (or registerWithTCC briefly
        // returned stale-true), fail fast rather than silently producing a dead tap.
        let trusted = RequiredPermission.accessibility.isGranted
        NSLog("KeyboardCapture: AXIsProcessTrusted = %@", trusted ? "true" : "false")
        guard trusted else {
            throw KeyboardCaptureError.accessibilityNotTrusted
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Store self as an unmanaged pointer to pass through the C callback
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardEventCallback,
            userInfo: selfPointer
        ) else {
            NSLog("KeyboardCapture: CGEvent.tapCreate returned nil (AXIsProcessTrusted was true)")
            throw KeyboardCaptureError.eventTapCreationFailed
        }
        NSLog("KeyboardCapture: event tap created successfully")

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw KeyboardCaptureError.runLoopSourceCreationFailed
        }

        eventTap = tap
        runLoopSource = source

        // Service the tap on a dedicated, high-priority thread so a blocked
        // main thread can never stall it (see the type doc above).
        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.runLoopReady.signal()

            // A timed run loop (rather than a bare CFRunLoopRun) guarantees
            // the cancellation flag is re-checked even if CFRunLoopStop races
            // the wakeup during shutdown.
            while !Thread.current.isCancelled {
                _ = CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
        }
        thread.name = "com.modaliser.keyboard-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        // Block until the thread has published its run loop and enabled the
        // tap, so a subsequent stop() always has a run loop to stop.
        runLoopReady.wait()
        NSLog("KeyboardCapture: tap enabled on dedicated thread")
    }

    /// Stop capturing keyboard events and tear down the dedicated thread.
    func stop() {
        tapThread?.cancel()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = tapRunLoop {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            // Wake the run loop so the thread observes its cancellation flag.
            CFRunLoopStop(runLoop)
        }
        tapThread = nil
        tapRunLoop = nil
        eventTap = nil
        runLoopSource = nil
    }

    /// Magic value tagged onto re-injected CGEvents (in eventSourceUserData)
    /// so we recognise them when they re-enter our tap and pass them through
    /// instead of re-buffering. Picked to be unlikely to collide with anything
    /// else; if a future event source happens to use the same value we'd
    /// merely skip our normal dispatch for that event — a benign degradation.
    static let reInjectionMagic: Int64 = 0x4d6f64616c6c69ef  // "Modalliª"

    /// Called from the C callback on the dedicated tap thread.
    fileprivate func handleEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap gets disabled by the system (e.g. timeout), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Re-injected events (from optimistic-capture rollback) carry our
        // magic in eventSourceUserData — pass them through untouched so they
        // reach the focused app instead of looping back into the buffer.
        if event.getIntegerValueField(.eventSourceUserData) == Self.reInjectionMagic {
            return Unmanaged.passUnretained(event)
        }

        let isKeyDown = type == .keyDown
        let captured = CapturedKeyEvent(
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            isKeyDown: isKeyDown,
            modifiers: event.flags
        )

        let result = onKeyEvent(captured)

        switch result {
        case .suppress:
            return nil
        case .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    deinit {
        stop()
    }
}

// MARK: - C callback

/// CGEvent tap callback — must be a free function (not a closure).
/// Bridges to the KeyboardCapture instance via the userInfo pointer.
private func keyboardEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let capture = Unmanaged<KeyboardCapture>.fromOpaque(userInfo).takeUnretainedValue()
    return capture.handleEvent(proxy, type: type, event: event)
}
