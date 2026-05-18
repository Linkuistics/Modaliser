import AppKit

/// Caches discovered windows across space changes and tracks focus order.
/// Windows found via AX on each space are cached. When you switch spaces,
/// cached windows from previously visited spaces persist in the list.
/// Focus history ensures the previously focused window is always first,
/// enabling quick Alt-Tab-like switching.
final class WindowCache {
    static let shared = WindowCache()

    /// Focus history: PIDs ordered by most recently focused, most recent first.
    private var focusHistory: [pid_t] = []

    /// Cached windows from other spaces, keyed by "pid:title" for stable identity.
    private var otherSpaceCache: [String: WindowInfo] = [:]

    /// Guards focusHistory and otherSpaceCache. listWindows() can be called
    /// from any thread (e.g. Scheme's main-queue dispatch races with workspace
    /// notification observers also touching the cache). Without this lock the
    /// dictionary's CoW machinery can crash with garbage tagged-pointer reads.
    private let lock = NSLock()

    private var activateObserver: Any?
    private var terminateObserver: Any?

    private init() {}

    /// Start observing app lifecycle events.
    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        // Track focus changes for ordering
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.recordFocusChange(pid: app.processIdentifier)
        }

        // Remove cache entries when apps quit
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeApp(pid: app.processIdentifier)
        }

        // Seed focus history with the current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recordFocusChange(pid: frontmost.processIdentifier)
        }
    }

    /// AX-enumerated windows on the current space only — no merge with the
    /// other-space cache, no Phase 3 zero-bounds entries. The window picker
    /// (numbered chip selector) uses this so digits map 1..N to actually-
    /// visible windows; cached entries from other spaces still hold their
    /// previously-captured bounds and would otherwise paint phantom chips
    /// or steal label slots.
    func listCurrentSpaceWindows() -> [WindowInfo] {
        lock.lock()
        defer { lock.unlock() }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        // Phase 1 only — sorted by focus recency the same way listWindows()
        // does, so the most recently focused on-screen window leads.
        var windows = currentSpaceWindowsViaAX(currentPID: currentPID).windows
        let switchingFromPID = focusHistory.first { $0 != currentPID }
        windows.sort { lhs, rhs in
            let lhsIsCurrent = lhs.ownerPID == switchingFromPID
            let rhsIsCurrent = rhs.ownerPID == switchingFromPID
            if lhsIsCurrent != rhsIsCurrent {
                return !lhsIsCurrent
            }
            return focusRank(for: lhs.ownerPID) < focusRank(for: rhs.ownerPID)
        }
        return windows
    }

    /// List windows: fresh AX for current space, cached for other spaces, sorted by focus recency.
    func listWindows() -> [WindowInfo] {
        lock.lock()
        defer { lock.unlock() }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))

        // Prune cache and focus history for apps that quit
        otherSpaceCache = otherSpaceCache.filter { runningPIDs.contains($0.value.ownerPID) }
        focusHistory.removeAll { !runningPIDs.contains($0) }

        // Phase 1: AX enumeration for current space (also re-caches into
        // otherSpaceCache so future cross-space lookups stay fresh).
        let phase1 = currentSpaceWindowsViaAX(currentPID: currentPID)
        let currentSpaceWindows = phase1.windows
        let currentSpacePIDs = phase1.pids

        // Phase 2: Merge cached windows from other spaces
        // Include cached entries for PIDs not seen in current AX enumeration
        var otherSpaceWindows: [WindowInfo] = []
        var otherPIDsSeen: Set<pid_t> = []

        for (_, info) in otherSpaceCache {
            guard !currentSpacePIDs.contains(info.ownerPID),
                  !otherPIDsSeen.contains(info.ownerPID) else { continue }
            otherSpaceWindows.append(info)
            otherPIDsSeen.insert(info.ownerPID)
        }

        // Phase 3: Running apps with no windows anywhere (never visited their space)
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID,
                  !currentSpacePIDs.contains(app.processIdentifier),
                  !otherPIDsSeen.contains(app.processIdentifier),
                  !app.isHidden else { continue }

            let name = app.localizedName ?? ""
            guard !name.isEmpty else { continue }

            otherSpaceWindows.append(WindowInfo(
                windowId: 0,
                title: name,
                ownerName: name,
                ownerPID: app.processIdentifier,
                bundleId: app.bundleIdentifier ?? "",
                bounds: .zero
            ))
        }

        // Combine and sort by focus recency.
        // The app the user is switching FROM (most recent in focusHistory that isn't us)
        // goes to the end. The PREVIOUS app goes to the top — this is the Alt-Tab target.
        let switchingFromPID = focusHistory.first { $0 != currentPID }
        var allWindows = currentSpaceWindows + otherSpaceWindows
        allWindows.sort { lhs, rhs in
            let lhsIsCurrent = lhs.ownerPID == switchingFromPID
            let rhsIsCurrent = rhs.ownerPID == switchingFromPID
            if lhsIsCurrent != rhsIsCurrent {
                return !lhsIsCurrent  // current app goes to the end
            }
            return focusRank(for: lhs.ownerPID) < focusRank(for: rhs.ownerPID)
        }

        return allWindows
    }

    // MARK: - Private

    /// Phase 1 of listWindows: walk every regular running app, enumerate AX
    /// windows in its focused window list, and capture each window's bounds.
    /// Side-effect: refreshes otherSpaceCache with the freshly-captured
    /// entries so subsequent cross-space lookups don't lose state.
    /// Caller MUST hold `lock`.
    private func currentSpaceWindowsViaAX(currentPID: pid_t)
        -> (windows: [WindowInfo], pids: Set<pid_t>)
    {
        var windows: [WindowInfo] = []
        var pids: Set<pid_t> = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != currentPID else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let axWindows = WindowEnumerator.axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement],
                  !axWindows.isEmpty else { continue }

            // AX is authoritative for apps on the current space.
            // Remove stale cache entries for this app (handles closed windows).
            let pid = app.processIdentifier
            otherSpaceCache = otherSpaceCache.filter { $0.value.ownerPID != pid }

            for axWindow in axWindows {
                let subrole = WindowEnumerator.axAttribute(axWindow, kAXSubroleAttribute) as? String
                if let subrole, subrole != "AXStandardWindow" && subrole != "AXDialog" {
                    continue
                }
                if WindowEnumerator.axAttribute(axWindow, kAXMinimizedAttribute) as? Bool == true {
                    continue
                }

                let title = WindowEnumerator.axAttribute(axWindow, kAXTitleAttribute) as? String ?? ""
                guard !title.isEmpty else { continue }

                var windowId: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowId)

                let position = WindowEnumerator.axPosition(axWindow) ?? .zero
                let size = WindowEnumerator.axSize(axWindow) ?? .zero

                let info = WindowInfo(
                    windowId: windowId,
                    title: title,
                    ownerName: app.localizedName ?? "",
                    ownerPID: app.processIdentifier,
                    bundleId: app.bundleIdentifier ?? "",
                    bounds: CGRect(origin: position, size: size)
                )
                windows.append(info)
                pids.insert(app.processIdentifier)

                // Re-cache with current state
                otherSpaceCache[cacheKey(info)] = info
            }
        }

        return (windows, pids)
    }

    private func removeApp(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        otherSpaceCache = otherSpaceCache.filter { $0.value.ownerPID != pid }
        focusHistory.removeAll { $0 == pid }
    }

    private func recordFocusChange(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        focusHistory.removeAll { $0 == pid }
        focusHistory.insert(pid, at: 0)
    }

    private func cacheKey(_ info: WindowInfo) -> String {
        "\(info.ownerPID):\(info.title)"
    }

    /// Lower rank = more recently focused = appears first.
    private func focusRank(for pid: pid_t) -> Int {
        if let index = focusHistory.firstIndex(of: pid) {
            return index
        }
        return Int.max
    }
}
