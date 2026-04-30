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

    /// Diagnostic file at ~/Library/Logs/Modaliser/window.log. We can't rely
    /// on NSLog reaching the unified log on every machine (some MDM-managed
    /// hosts suppress process logs), so we tee diagnostics to a file as well.
    private static let diagLogURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Modaliser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("window.log")
    }()

    private static let diagFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func diag(_ message: String) {
        NSLog("%@", message)
        let line = "\(diagFormatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: diagLogURL.path),
           let handle = try? FileHandle(forWritingTo: diagLogURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: diagLogURL)
        }
    }

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
        guard let appElement = focusedAppElement() else {
            diag("WindowManipulator: no focused application via AX or NSWorkspace")
            return nil
        }
        guard let window = focusedWindowOf(app: appElement) else {
            diag("WindowManipulator: no focused window via any AX path")
            return nil
        }
        guard let position = axPosition(window),
              let size = axSize(window) else {
            diag("WindowManipulator: window has no position/size")
            return nil
        }
        return (window, CGRect(origin: position, size: size))
    }

    /// Resolve the focused-app AX element, falling back to NSWorkspace when
    /// the AX system-wide query returns nil. Some screen-sharing / managed
    /// sessions don't populate kAXFocusedApplicationAttribute even when AX
    /// permission is granted and NSWorkspace correctly tracks the frontmost
    /// application.
    private static func focusedAppElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedApp = axAttribute(systemWide, kAXFocusedApplicationAttribute) {
            diag("WindowManipulator: app via AX systemwide")
            return (focusedApp as! AXUIElement)
        }
        if let running = NSWorkspace.shared.frontmostApplication {
            diag(
                "WindowManipulator: app via NSWorkspace fallback "
                + "pid=\(running.processIdentifier) "
                + "bundle=\(running.bundleIdentifier ?? "?")")
            return AXUIElementCreateApplication(running.processIdentifier)
        }
        return nil
    }

    /// Resolve the focused window for an app element with fallbacks.
    ///
    /// Electron apps (Slack et al) run in an "on-demand AX" mode where the AX
    /// tree is empty until a client requests it via AXManualAccessibility. We
    /// flip that flag first, then retry the standard resolution paths with a
    /// short backoff while the app populates its tree.
    private static func focusedWindowOf(app: AXUIElement) -> AXUIElement? {
        AXUIElementSetAttributeValue(
            app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var lastFW: AXError = .success
        var lastMW: AXError = .success
        var lastWS: AXError = .success
        for attempt in 0..<5 {
            var obj: AnyObject?
            lastFW = AXUIElementCopyAttributeValue(
                app, kAXFocusedWindowAttribute as CFString, &obj)
            if lastFW == .success, let obj {
                diag("WindowManipulator: window via AXFocusedWindow attempt=\(attempt)")
                return (obj as! AXUIElement)
            }
            lastMW = AXUIElementCopyAttributeValue(
                app, kAXMainWindowAttribute as CFString, &obj)
            if lastMW == .success, let obj {
                diag("WindowManipulator: window via AXMainWindow attempt=\(attempt)")
                return (obj as! AXUIElement)
            }
            lastWS = AXUIElementCopyAttributeValue(
                app, kAXWindowsAttribute as CFString, &obj)
            if lastWS == .success, let arr = obj as? [AXUIElement], let first = arr.first {
                diag("WindowManipulator: window via AXWindows[0] attempt=\(attempt)")
                return first
            }
            if attempt < 4 { usleep(20_000) }
        }
        diag(
            "WindowManipulator: AX resolution failed "
            + "FW=\(lastFW.rawValue) MW=\(lastMW.rawValue) WS=\(lastWS.rawValue)")
        dumpCGWindowsForApp(app)
        return nil
    }

    /// Dump CGWindowList entries for the given AX app element's pid, so we can
    /// see whether the windows are visible at all (and under which pid).
    private static func dumpCGWindowsForApp(_ app: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success else { return }
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            diag("WindowManipulator: CGWindowList unavailable")
            return
        }
        var matches = 0
        for info in infoList {
            let owner = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            if owner == pid {
                matches += 1
                diag(
                    "WindowManipulator: CG window pid=\(owner) "
                    + "owner=\"\(name)\" title=\"\(title)\" layer=\(layer)")
            }
        }
        if matches == 0 {
            diag("WindowManipulator: no CG windows for pid=\(pid) "
                + "(searched \(infoList.count) entries)")
        }
    }

    private static func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// Run AX position/size mutations with the owning app's
    /// AXEnhancedUserInterface flag temporarily disabled. Electron apps and
    /// some others set this flag — when it's on, `AXUIElementSetAttributeValue`
    /// for AXSize/AXPosition silently no-ops. The flag is restored to its
    /// prior value afterward so the app's accessibility behavior is unchanged.
    ///
    /// After flipping EUI off we briefly wait so the target app has a runloop
    /// tick to actually process the flag change. Without this delay, Electron
    /// can silently drop the AXSize/AXPosition writes because internally it's
    /// still in EUI mode when they arrive.
    private static func withResizableApp(_ window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid > 0 else {
            body()
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let wasEnhanced = (axAttribute(app, "AXEnhancedUserInterface") as? Bool) ?? false
        diag("WindowManipulator: pid=\(pid) EUI=\(wasEnhanced)")
        if wasEnhanced {
            AXUIElementSetAttributeValue(
                app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            usleep(50_000)
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
            let err = AXUIElementSetAttributeValue(
                window, kAXPositionAttribute as CFString, value)
            diag("WindowManipulator: setPosition x=\(x) y=\(y) err=\(err.rawValue)")
        }
    }

    private static func setWindowSize(_ window: AXUIElement, width: CGFloat, height: CGFloat) {
        var size = CGSize(width: width, height: height)
        if let value = AXValueCreate(.cgSize, &size) {
            let err = AXUIElementSetAttributeValue(
                window, kAXSizeAttribute as CFString, value)
            diag("WindowManipulator: setSize w=\(width) h=\(height) err=\(err.rawValue)")
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
