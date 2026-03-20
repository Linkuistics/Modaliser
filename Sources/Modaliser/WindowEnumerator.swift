import AppKit

/// Information about a visible window, extracted from CGWindowList.
struct WindowInfo {
    let windowId: CGWindowID
    let title: String
    let ownerName: String
    let ownerPID: pid_t
    let bundleId: String
    let bounds: CGRect
}

/// Enumerates visible windows using CGWindowListCopyWindowInfo.
enum WindowEnumerator {

    /// List all visible windows, excluding the current app and empty-titled windows.
    /// Ordered by most recently focused (front to back).
    static func listVisibleWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        return windowList.compactMap { info -> WindowInfo? in
            guard let windowId = info[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0  // Normal window layer only
            else { return nil }

            // Skip our own windows
            guard ownerPID != currentPID else { return nil }

            let title = info[kCGWindowName as String] as? String ?? ""
            // Skip windows with no title (menu bar items, etc.)
            guard !title.isEmpty else { return nil }

            let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            let bundleId = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""

            return WindowInfo(
                windowId: windowId,
                title: title,
                ownerName: ownerName,
                ownerPID: ownerPID,
                bundleId: bundleId,
                bounds: bounds
            )
        }
    }
}
