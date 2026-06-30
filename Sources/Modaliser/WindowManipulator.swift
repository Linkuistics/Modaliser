import AppKit

/// Manipulates windows using the macOS Accessibility API.
/// Requires Accessibility permissions to function.
enum WindowManipulator {

    /// One display's identity + AX-visible-frame geometry, used by
    /// `(list-displays)` to power display-chip placement and the
    /// proportional move-remap. `frame` is the visible frame (menu bar +
    /// Dock excluded) in AX top-left coords — the same space `move-window`
    /// and `hints-show` use. `id` is the stable CGDirectDisplayID.
    struct DisplayInfo {
        let id: CGDirectDisplayID
        let frame: CGRect
        let isPrimary: Bool
    }

    /// All displays, left-to-right by visible-frame x. `is-primary` flags
    /// `NSScreen.screens[0]` (the menu-bar display) regardless of sort
    /// position — a display to the left has a smaller x but isn't primary.
    static func listDisplays() -> [DisplayInfo] {
        let primary = NSScreen.screens.first
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
            return DisplayInfo(
                id: id,
                frame: axVisibleFrame(for: screen),
                isPrimary: screen === primary)
        }.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

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

    /// Absolute placement of the focused window in AX coords — the absolute
    /// sibling of fractional `moveFocusedWindow`. Resolves the window via the
    /// same cold-AX-safe path, saves its frame first (so `restore-window`
    /// still works), and wraps the writes in `withResizableApp` (the EUI flip).
    static func setFocusedWindowFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        guard let (window, frame) = focusedWindowAndFrame() else { return }
        saveFrame(window, frame: frame)
        withResizableApp(window) {
            setWindowPosition(window, x: x, y: y)
            setWindowSize(window, width: width, height: height)
        }
    }

    /// Give keyboard focus to display `id` so macOS Space / Mission-Control
    /// keyboard commands act on it. (1) Find the topmost regular window whose
    /// bounds-centre lies on the display by walking CGWindowList front-to-back
    /// (z-order); raise it (AXRaise + AXMain + AXFocused) and activate its app.
    /// (2) Warp the mouse to the display centre. (3) If no window was found,
    /// synthesize a desktop click so the display still becomes active.
    static func focusDisplay(_ id: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(id)   // global display coords, top-left origin
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let myPID = ProcessInfo.processInfo.processIdentifier
        var raised = false

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      pid != myPID,
                      let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                      layer == 0,   // 0 == normal app window layer; skip menus/overlays
                      let b = entry[kCGWindowBounds as String] as? [String: Any],
                      let bx = (b["X"] as? NSNumber)?.doubleValue,
                      let by = (b["Y"] as? NSNumber)?.doubleValue,
                      let bw = (b["Width"] as? NSNumber)?.doubleValue,
                      let bh = (b["Height"] as? NSNumber)?.doubleValue
                else { continue }
                let windowCenter = CGPoint(x: bx + bw / 2, y: by + bh / 2)
                if !bounds.contains(windowCenter) { continue }

                // Best-effort: raise the AX window whose origin matches this
                // CGWindowList entry, then activate the owning app.
                let appElement = AXUIElementCreateApplication(pid)
                if let windows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] {
                    for w in windows {
                        if let pos = axPosition(w),
                           abs(pos.x - bx) < 2, abs(pos.y - by) < 2 {
                            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                            AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                            break
                        }
                    }
                }
                NSRunningApplication(processIdentifier: pid)?.activate()
                raised = true
                break
            }
        }

        warpMouse(to: center)
        if !raised {
            synthesizeClick(at: center)
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
    static func axVisibleFrame(for screen: NSScreen) -> CGRect {
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

    /// Identity + frame of the currently focused window, or nil when nothing
    /// regular is focused. Resolved by the same cold-AX-safe path the layout
    /// ops use (frontmost-app → kAXFocusedWindow/kAXMainWindow), plus
    /// `_AXUIElementGetWindow` for the CGWindowID and `AXUIElementGetPid` for
    /// the owner pid. `windowId` is 0 when the private SPI can't resolve it —
    /// the cursor-seed matcher's PID+origin fallback covers that residual
    /// case (list-cursor-window-focus-k28). Coordinates are AX top-left
    /// origin, matching `list-current-space-windows`, so the matcher can
    /// compare frame origins directly against the window-list rows.
    static func focusedWindowIdentity()
        -> (ownerPid: pid_t, windowId: CGWindowID, frame: CGRect)? {
        guard let (window, frame) = focusedWindowAndFrame() else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        var windowId: CGWindowID = 0
        _ = _AXUIElementGetWindow(window, &windowId)
        return (ownerPid: pid, windowId: windowId, frame: frame)
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

    /// Warp the cursor to `p` and post a synthetic mouse-moved event so the
    /// window server registers the cursor on the destination display.
    private static func warpMouse(to p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: p, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
    }

    /// Synthesize a left click at `p` — used only when no window was found on
    /// the target display, so the desktop click still makes the display active.
    private static func synthesizeClick(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: p, mouseButton: .left),
           let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                            mouseCursorPosition: p, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
