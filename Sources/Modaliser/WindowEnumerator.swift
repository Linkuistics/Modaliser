import AppKit

/// Information about a visible window.
struct WindowInfo {
    let windowId: CGWindowID
    let title: String
    let ownerName: String
    let ownerPID: pid_t
    let bundleId: String
    let bounds: CGRect
}

/// Enumerates windows using a hybrid of the Accessibility API and CGWindowList.
/// - AX for current-space windows: accurate titles, proper subrole filtering
/// - CGWindowList for other-space windows: discovers windows AX can't see
/// Requires Accessibility permission. Screen Recording improves other-space window titles.
enum WindowEnumerator {

    static func listVisibleWindows() -> [WindowInfo] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var windows: [WindowInfo] = []
        var pidsSeen: Set<pid_t> = []

        // Phase 1: AX enumeration — current space, accurate
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement],
                  !axWindows.isEmpty else { continue }

            pidsSeen.insert(app.processIdentifier)

            for axWindow in axWindows {
                let subrole = axAttribute(axWindow, kAXSubroleAttribute) as? String
                if let subrole, subrole != "AXStandardWindow" && subrole != "AXDialog" {
                    continue
                }
                if axAttribute(axWindow, kAXMinimizedAttribute) as? Bool == true {
                    continue
                }

                let title = axAttribute(axWindow, kAXTitleAttribute) as? String ?? ""
                guard !title.isEmpty else { continue }

                var windowId: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowId)

                let position = axPosition(axWindow) ?? .zero
                let size = axSize(axWindow) ?? .zero

                windows.append(WindowInfo(
                    windowId: windowId,
                    title: title,
                    ownerName: app.localizedName ?? "",
                    ownerPID: app.processIdentifier,
                    bundleId: app.bundleIdentifier ?? "",
                    bounds: CGRect(origin: position, size: size)
                ))
            }
        }

        // Phase 2: CGWindowList — find windows from apps not seen in AX (other spaces)
        guard let cgWindows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return windows
        }

        // Group CGWindowList entries by PID, keeping only relevant ones
        var otherSpaceApps: [pid_t: (name: String, bundleId: String, title: String, windowId: CGWindowID, bounds: CGRect)] = [:]

        for info in cgWindows {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  ownerPID != currentPID,
                  !pidsSeen.contains(ownerPID) else { continue }

            guard let app = NSRunningApplication(processIdentifier: ownerPID),
                  app.activationPolicy == .regular else { continue }

            // Use the CGWindowList title if available (needs Screen Recording), else app name
            let cgTitle = info[kCGWindowName as String] as? String ?? ""
            let title = cgTitle.isEmpty ? (app.localizedName ?? "") : cgTitle
            guard !title.isEmpty else { continue }

            let windowId = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            guard bounds.width >= 50, bounds.height >= 50 else { continue }

            // Keep only the first (most recent) window per other-space app
            if otherSpaceApps[ownerPID] == nil {
                otherSpaceApps[ownerPID] = (
                    name: app.localizedName ?? "",
                    bundleId: app.bundleIdentifier ?? "",
                    title: title,
                    windowId: windowId,
                    bounds: bounds
                )
            }
        }

        for (pid, info) in otherSpaceApps {
            windows.append(WindowInfo(
                windowId: info.windowId,
                title: info.title,
                ownerName: info.name,
                ownerPID: pid,
                bundleId: info.bundleId,
                bounds: info.bounds
            ))
        }

        return windows
    }

    // MARK: - AX helpers

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
