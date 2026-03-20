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

        var windows = windowList.compactMap { info -> WindowInfo? in
            guard let windowId = info[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0  // Normal window layer only
            else { return nil }

            // Skip our own windows
            guard ownerPID != currentPID else { return nil }

            // kCGWindowName requires Screen Recording permission on macOS 10.15+.
            // Without it, titles are nil. Fall back to owner name so the list is still usable.
            let title = info[kCGWindowName as String] as? String ?? ""
            let displayTitle = title.isEmpty ? ownerName : title
            guard !displayTitle.isEmpty else { return nil }

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
                title: displayTitle,
                ownerName: ownerName,
                ownerPID: ownerPID,
                bundleId: bundleId,
                bounds: bounds
            )
        }

        // Disambiguate duplicate titles by appending a counter: "Zed", "Zed (2)", "Zed (3)"
        var titleCounts: [String: Int] = [:]
        for i in windows.indices {
            let title = windows[i].title
            let count = (titleCounts[title] ?? 0) + 1
            titleCounts[title] = count
            if count > 1 {
                windows[i] = WindowInfo(
                    windowId: windows[i].windowId,
                    title: "\(title) (\(count))",
                    ownerName: windows[i].ownerName,
                    ownerPID: windows[i].ownerPID,
                    bundleId: windows[i].bundleId,
                    bounds: windows[i].bounds
                )
            }
        }

        return windows
    }
}
