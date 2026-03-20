import AppKit

/// Information about a visible window, extracted from the Accessibility API.
struct WindowInfo {
    let windowId: CGWindowID
    let title: String
    let ownerName: String
    let ownerPID: pid_t
    let bundleId: String
    let bounds: CGRect
}

/// Enumerates windows using the Accessibility API (AXUIElement).
/// This finds real user windows across all spaces, matching Hammerspoon's hs.window.filter.
/// Requires Accessibility permission (already granted for keyboard capture).
enum WindowEnumerator {

    /// List standard windows from all running apps, across all spaces.
    /// Excludes the currently focused window (you're switching away from it).
    static func listVisibleWindows() -> [WindowInfo] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let focusedWindow = getFocusedWindowId()
        var windows: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                // Only include standard windows (not sheets, dialogs, utility panels)
                guard let subrole = axAttribute(axWindow, kAXSubroleAttribute) as? String,
                      subrole == "AXStandardWindow" else { continue }

                let title = axAttribute(axWindow, kAXTitleAttribute) as? String ?? ""
                guard !title.isEmpty else { continue }

                // Get window ID for deduplication with focused window
                var windowId: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowId)

                // Skip the currently focused window
                if windowId == focusedWindow { continue }

                let position = axPosition(axWindow) ?? .zero
                let size = axSize(axWindow) ?? .zero
                let bounds = CGRect(origin: position, size: size)

                windows.append(WindowInfo(
                    windowId: windowId,
                    title: title,
                    ownerName: app.localizedName ?? "",
                    ownerPID: app.processIdentifier,
                    bundleId: app.bundleIdentifier ?? "",
                    bounds: bounds
                ))
            }
        }

        return windows
    }

    // MARK: - Private

    private static func getFocusedWindowId() -> CGWindowID {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApp = axAttribute(systemWide, kAXFocusedApplicationAttribute) else {
            return 0
        }
        let appElement = focusedApp as! AXUIElement
        guard let focusedWindow = axAttribute(appElement, kAXFocusedWindowAttribute) else {
            return 0
        }
        let window = focusedWindow as! AXUIElement
        var windowId: CGWindowID = 0
        _ = _AXUIElementGetWindow(window, &windowId)
        return windowId
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

// Private SPI: get CGWindowID from AXUIElement. Used by Hammerspoon, AltTab, etc.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError
