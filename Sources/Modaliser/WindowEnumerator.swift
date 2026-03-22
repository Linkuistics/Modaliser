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

/// Enumerates windows using the Accessibility API, with running-app fallback for other spaces.
/// - AX for current-space windows: accurate titles, proper subrole filtering
/// - Running apps list for other-space apps: AX and CGWindowList can't see other spaces,
///   so we add an app-level entry. Selecting it calls app.activate() which switches spaces.
/// Requires Accessibility permission. No Screen Recording needed.
enum WindowEnumerator {

    static func listVisibleWindows() -> [WindowInfo] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var windows: [WindowInfo] = []
        var pidsSeen: Set<pid_t> = []

        // Phase 1: AX enumeration — current space, accurate titles and filtering
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement],
                  !axWindows.isEmpty else { continue }

            var appHasWindows = false

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
                appHasWindows = true
            }

            if appHasWindows {
                pidsSeen.insert(app.processIdentifier)
            }
        }

        // Sort Phase 1 windows by front-to-back order (MRU) using CGWindowList
        let cgOrder = Self.windowOrderByFrontToBack()
        windows.sort { a, b in
            let aOrder = cgOrder[a.windowId] ?? Int.max
            let bOrder = cgOrder[b.windowId] ?? Int.max
            return aOrder < bOrder
        }

        // Phase 2: Running apps with no AX windows — these are on other spaces.
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID,
                  !pidsSeen.contains(app.processIdentifier),
                  !app.isHidden else { continue }

            let name = app.localizedName ?? ""
            guard !name.isEmpty else { continue }

            windows.append(WindowInfo(
                windowId: 0,
                title: name,
                ownerName: name,
                ownerPID: app.processIdentifier,
                bundleId: app.bundleIdentifier ?? "",
                bounds: .zero
            ))
        }

        return windows
    }

    // MARK: - Window ordering

    /// Get front-to-back window order from CGWindowList.
    /// Returns a map of windowId → position (0 = frontmost).
    /// Uses optionAll to include windows on other Spaces.
    private static func windowOrderByFrontToBack() -> [CGWindowID: Int] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (i, info) in infoList.enumerated() {
            if let id = info[kCGWindowNumber as String] as? Int {
                order[CGWindowID(id)] = i
            }
        }
        return order
    }

    // MARK: - AX helpers

    static func axAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    static func axPosition(_ element: AXUIElement) -> CGPoint? {
        guard let value = axAttribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    static func axSize(_ element: AXUIElement) -> CGSize? {
        guard let value = axAttribute(element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}

// Private SPI: get CGWindowID from AXUIElement. Used by Hammerspoon, AltTab, etc.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError
