import AppKit

/// Manipulates windows using the macOS Accessibility API.
/// Requires Accessibility permissions to function.
enum WindowManipulator {

    /// Activate an app by PID — switches to its Space if on another Space.
    static func activateApp(ownerPID: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: ownerPID) else { return }
        app.activate()
    }

    /// Focus a specific window by its owner PID and title (current Space only).
    static func focusWindow(ownerPID: pid_t, title: String) {
        guard let app = NSRunningApplication(processIdentifier: ownerPID) else { return }

        let appElement = AXUIElementCreateApplication(ownerPID)
        guard let windows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { return }

        for window in windows {
            if let windowTitle = axAttribute(window, kAXTitleAttribute) as? String,
               windowTitle == title {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                app.activate()
                break
            }
        }
    }

    /// Center the focused window on its current screen.
    static func centerFocusedWindow() {
        guard let (window, frame) = focusedWindowAndFrame() else { return }
        guard let screen = screenContaining(frame) else { return }
        let visibleFrame = axVisibleFrame(for: screen)

        let newX = visibleFrame.origin.x + (visibleFrame.width - frame.width) / 2
        let newY = visibleFrame.origin.y + (visibleFrame.height - frame.height) / 2
        withResizableApp(window) {
            setWindowPosition(window, x: newX, y: newY)
        }
    }

    /// Move the focused window to a unit rectangle (fractions of visible screen).
    /// Coordinates use top-left origin: y=0 is the top of the visible area.
    /// Width and height are clamped so the window never extends past the visible area.
    /// e.g. (0, 0, 1/3, 1) = left third, (0, 1/2, 1/3, 1) = bottom half of left third
    static func moveFocusedWindow(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        guard let (window, frame) = focusedWindowAndFrame() else { return }
        guard let screen = screenContaining(frame) else { return }
        saveFrame(window, frame: frame)
        let visibleFrame = axVisibleFrame(for: screen)

        let clampedW = min(width, 1.0 - x)
        let clampedH = min(height, 1.0 - y)

        let newX = visibleFrame.origin.x + visibleFrame.width * x
        let newY = visibleFrame.origin.y + visibleFrame.height * y
        let newW = visibleFrame.width * clampedW
        let newH = visibleFrame.height * clampedH

        withResizableApp(window) {
            setWindowPosition(window, x: newX, y: newY)
            setWindowSize(window, width: newW, height: newH)
        }
    }

    /// Toggle fullscreen on the focused window.
    static func toggleFullscreen() {
        guard let (window, frame) = focusedWindowAndFrame() else { return }
        saveFrame(window, frame: frame)
        AXUIElementSetAttributeValue(
            window,
            "AXFullScreen" as CFString,
            !(axAttribute(window, "AXFullScreen") as? Bool ?? false) as CFBoolean
        )
    }

    /// Restore the focused window to its previously saved frame.
    /// Exits fullscreen first if needed.
    static func restoreFocusedWindow() {
        guard let (window, _) = focusedWindowAndFrame() else { return }
        guard let saved = savedFrames[windowKey(window)] else { return }

        // Exit fullscreen before restoring — AX ignores position/size changes in fullscreen
        if let isFS = axAttribute(window, "AXFullScreen") as? Bool, isFS {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            // Delay to let the fullscreen exit animation complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withResizableApp(window) {
                    setWindowPosition(window, x: saved.origin.x, y: saved.origin.y)
                    setWindowSize(window, width: saved.width, height: saved.height)
                }
            }
            return
        }

        withResizableApp(window) {
            setWindowPosition(window, x: saved.origin.x, y: saved.origin.y)
            setWindowSize(window, width: saved.width, height: saved.height)
        }
    }

    // MARK: - Private

    /// Convert an NSScreen's visibleFrame from Cocoa coordinates (bottom-left origin)
    /// to screen coordinates (top-left origin) used by the Accessibility API.
    private static func axVisibleFrame(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens[0].frame.height
        let cocoa = screen.visibleFrame
        return CGRect(
            x: cocoa.origin.x,
            y: primaryHeight - cocoa.origin.y - cocoa.height,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    private static var savedFrames: [String: CGRect] = [:]

    private static func saveFrame(_ window: AXUIElement, frame: CGRect) {
        savedFrames[windowKey(window)] = frame
    }

    private static func windowKey(_ window: AXUIElement) -> String {
        let title = axAttribute(window, kAXTitleAttribute) as? String ?? ""
        let pid = axAttribute(window, "AXPid") as? pid_t ?? 0
        return "\(pid):\(title)"
    }

    private static func focusedWindowAndFrame() -> (AXUIElement, CGRect)? {
        // Resolve the target app via NSWorkspace.frontmostApplication — a
        // window-server API independent of the target app's accessibility
        // state — rather than AXUIElementCreateSystemWide() +
        // kAXFocusedApplicationAttribute. Chromium/Electron apps keep their
        // accessibility engine dormant until an assistive client warms it, and
        // while it is dormant the system-wide focused-application attribute
        // returns kAXErrorNoValue, so the old path resolved to nil and the
        // layout op silently no-op'd (the "Cold-AX resolution gap"). Building
        // the app element directly from the frontmost PID works cold.
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        // kAXFocusedWindow, falling back to kAXMainWindow — both resolve while
        // a Chromium app is cold (010 evidence); the system-wide attribute is
        // the only one that does not.
        guard let windowObj = axAttribute(appElement, kAXFocusedWindowAttribute)
                ?? axAttribute(appElement, kAXMainWindowAttribute) else {
            return nil
        }
        let window = windowObj as! AXUIElement
        guard let position = axPosition(window),
              let size = axSize(window) else {
            return nil
        }
        return (window, CGRect(origin: position, size: size))
    }

    private static func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// Run AX position/size mutations with the owning app's
    /// AXEnhancedUserInterface flag temporarily disabled. Apps that honor this
    /// flag (Slack and some other Electron apps) silently no-op AX
    /// position/size writes while it is on, so we flip it off, issue the
    /// writes, then restore it to leave the app's accessibility behavior
    /// unchanged.
    ///
    /// No settle delay between the flip and the writes: diagnosis 010 varied a
    /// settle delay across 0 / 50 / 500 ms and the writes always landed
    /// (returned .success and read back at target) regardless. The previous
    /// `usleep(50_000)` was tuned to one machine's speed for a write-drop that
    /// does not actually occur, so it is gone — the flip is timing-robust by
    /// construction. See docs/adr/0010 and CONTEXT.md ("Cold-AX resolution
    /// gap", "EUI-settle race [refuted]").
    private static func withResizableApp(_ window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid > 0 else {
            body()
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let wasEnhanced = (axAttribute(app, "AXEnhancedUserInterface") as? Bool) ?? false
        if wasEnhanced {
            AXUIElementSetAttributeValue(
                app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        body()
        if wasEnhanced {
            AXUIElementSetAttributeValue(
                app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private static func setWindowPosition(_ window: AXUIElement, x: CGFloat, y: CGFloat) {
        var point = CGPoint(x: x, y: y)
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func setWindowSize(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
        var size = CGSize(width: width, height: height)
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    private static func axAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private static func axPosition(_ element: AXUIElement) -> CGPoint? {
        guard let value = axAttribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private static func axSize(_ element: AXUIElement) -> CGSize? {
        guard let value = axAttribute(element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}
