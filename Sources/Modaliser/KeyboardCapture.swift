import AppKit
import CoreGraphics

/// Captures global keyboard events via a CGEvent tap.
/// Requires Accessibility permissions to function.
final class KeyboardCapture {
    private var onKeyEvent: (CapturedKeyEvent) -> KeyEventHandlingResult
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        guard AccessibilityPermission.isTrusted() else {
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
            throw KeyboardCaptureError.eventTapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw KeyboardCaptureError.runLoopSourceCreationFailed
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stop capturing keyboard events and clean up resources.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Called from the C callback on the main thread.
    fileprivate func handleEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap gets disabled by the system (e.g. timeout), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
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
