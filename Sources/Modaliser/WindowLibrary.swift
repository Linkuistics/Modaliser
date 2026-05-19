import AppKit
import LispKit

/// Native LispKit library providing window management.
/// Scheme name: (modaliser window)
///
/// Provides: list-windows, focus-window, center-window, move-window,
///           toggle-fullscreen, restore-window
final class WindowLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "window"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define", "assoc", "cdr")
    }

    public override func declarations() {
        self.define(Procedure("list-windows", listWindowsFunction))
        self.define(Procedure("list-current-space-windows", listCurrentSpaceWindowsFunction))
        self.define(Procedure("focus-window", focusWindowFunction))
        self.define(Procedure("center-window", centerWindowFunction))
        self.define(Procedure("move-window", moveWindowFunction))
        self.define(Procedure("toggle-fullscreen", toggleFullscreenFunction))
        self.define(Procedure("restore-window", restoreWindowFunction))
        self.define(Procedure("primary-screen-size", primaryScreenSizeFunction))
        self.define(Procedure("window-visible-at?", windowVisibleAtFunction))
        self.define(Procedure("find-chip-position", findChipPositionFunction))
    }

    // MARK: - Functions

    /// (list-windows) → list of alists
    /// Each entry: text (title), subText (app name), icon (bundleId), iconType, windowId, ownerPid
    private func listWindowsFunction() -> Expr {
        let windows = WindowCache.shared.listWindows()
        var result: Expr = .null
        for window in windows.reversed() {
            let alist = makeWindowAlist(window)
            result = .pair(alist, result)
        }
        return result
    }

    /// (list-current-space-windows) → list of alists
    /// Each entry: text, subText, icon, iconType, windowId, ownerPid, x, y, w, h
    /// Returns only windows AX-enumerated on the current space (Phase 1).
    /// Excludes the other-space cache — those entries hold stale bounds
    /// from when their app last had a window on a visited space, so
    /// including them would paint phantom chips at no-longer-meaningful
    /// coordinates and steal label slots from genuinely visible windows.
    private func listCurrentSpaceWindowsFunction() -> Expr {
        let windows = WindowCache.shared.listCurrentSpaceWindows()
        var result: Expr = .null
        for window in windows.reversed() {
            let alist = makeCurrentSpaceWindowAlist(window)
            result = .pair(alist, result)
        }
        return result
    }

    /// (focus-window choice-alist) → void
    private func focusWindowFunction(_ choice: Expr) throws -> Expr {
        guard let pid = SchemeAlistLookup.lookupFixnum(choice, key: "ownerPid") else {
            return .void
        }
        let windowId = SchemeAlistLookup.lookupFixnum(choice, key: "windowId") ?? 0
        let title = SchemeAlistLookup.lookupString(choice, key: "text") ?? ""

        if windowId == 0 {
            WindowManipulator.activateApp(ownerPID: pid_t(pid))
        } else {
            WindowManipulator.focusWindow(ownerPID: pid_t(pid), title: title)
        }
        return .void
    }

    /// (center-window) → void
    private func centerWindowFunction() -> Expr {
        WindowManipulator.centerFocusedWindow()
        return .void
    }

    /// (move-window x y width height) → void
    /// All arguments are unit fractions (0.0-1.0) of the screen.
    private func moveWindowFunction(_ xExpr: Expr, _ yExpr: Expr,
                                     _ wExpr: Expr, _ hExpr: Expr) throws -> Expr {
        let x = try xExpr.asDouble(coerce: true)
        let y = try yExpr.asDouble(coerce: true)
        let w = try wExpr.asDouble(coerce: true)
        let h = try hExpr.asDouble(coerce: true)
        WindowManipulator.moveFocusedWindow(x: x, y: y, width: w, height: h)
        return .void
    }

    /// (toggle-fullscreen) → void
    private func toggleFullscreenFunction() -> Expr {
        WindowManipulator.toggleFullscreen()
        return .void
    }

    /// (restore-window) → void
    private func restoreWindowFunction() -> Expr {
        WindowManipulator.restoreFocusedWindow()
        return .void
    }

    /// (primary-screen-size) → ((w . W) (h . H))
    /// Dimensions of the primary screen in AX coordinates (the coordinate
    /// space windows and hint chips both live in). Used by chip-overlap
    /// resolution to clamp adjusted positions onscreen.
    private func primaryScreenSizeFunction() -> Expr {
        let screen = NSScreen.screens.first?.frame ?? .zero
        return SchemeAlistLookup.makeAlist([
            ("w", .fixnum(Int64(screen.width))),
            ("h", .fixnum(Int64(screen.height))),
        ], symbols: self.context.symbols)
    }

    /// (window-visible-at? wid pid x y) → #t/#f
    /// Returns #t when the window with id `wid` (owned by `pid`) is the
    /// topmost regular app window at screen point (x, y). The window-
    /// select chip uses this to test whether its center sits on its own
    /// window's pixels (full background) or on top of another window
    /// (washed-out background). Coordinates are AX top-left origin —
    /// same as list-current-space-windows returns.
    ///
    /// Matching falls back from strict windowId to owner-PID because
    /// _AXUIElementGetWindow (the private API WindowCache uses to fill
    /// each window's id) is observed to disagree with CGWindowList's
    /// kCGWindowNumber for some apps — the chip would otherwise dull
    /// even when its own window is genuinely frontmost. Same-app
    /// windows at the chip's point still count as "your own window."
    ///
    /// Translucent windows (alpha < 1.0) are skipped on the way down —
    /// dimming utilities like HazeOver draw a full-screen overlay
    /// between focused and unfocused windows. The user still sees their
    /// target through the tint, so the overlay shouldn't count as
    /// occluding. The target itself is matched first regardless of
    /// alpha, so a translucent target window still reads as visible.
    private func windowVisibleAtFunction(_ widExpr: Expr, _ pidExpr: Expr,
                                          _ xExpr: Expr, _ yExpr: Expr) throws -> Expr {
        let wid = try widExpr.asInt64()
        let pid = try pidExpr.asInt64()
        let x = try xExpr.asInt64()
        let y = try yExpr.asInt64()
        if wid == 0 && pid == 0 {
            return .true  // No identifiers to match — bias to visible.
        }
        let myPID = Int64(ProcessInfo.processInfo.processIdentifier)
        let pt = CGPoint(x: CGFloat(x), y: CGFloat(y))

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return .true  // No info — assume visible rather than fail soft.
        }

        for entry in list {
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let bx = (bounds["X"] as? NSNumber)?.doubleValue,
                  let by = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let bw = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let bh = (bounds["Height"] as? NSNumber)?.doubleValue
            else { continue }

            let rect = CGRect(x: bx, y: by, width: bw, height: bh)
            if !rect.contains(pt) { continue }

            let entryWid = (entry[kCGWindowNumber as String] as? NSNumber)?.int64Value ?? 0
            let entryPid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int64Value ?? 0

            // Skip our own panels (overlay, hint chips, etc.).
            if entryPid == myPID { continue }

            // Target match wins regardless of what's drawn on top of it —
            // a translucent overlay still leaves the target visible.
            if wid > 0 && entryWid == wid { return .true }
            if pid > 0 && entryPid == pid { return .true }

            // Skip translucent overlays (HazeOver-style dimmers, f.lux
            // blue-light filters, screen-tint utilities). They sit above
            // unfocused windows in z-order but don't pixel-occlude.
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha < 1.0 { continue }

            return .false
        }
        return .true  // No window covers this point.
    }

    /// (find-chip-position wid pid wx wy ww wh nx ny cw ch padding)
    ///   → ((x . X) (y . Y))   ;; placement for the chip's top-left
    ///   → #f                   ;; no fragment can host the chip
    ///
    /// Args:
    ///   wid, pid       — target window identity (matches `window-visible-at?`).
    ///   wx, wy, ww, wh — target window rect (AX top-left origin).
    ///   nx, ny         — caller-computed natural chip origin (the place
    ///                    the chip would land in the absence of occlusion;
    ///                    typically `(wx + ww·offset-frac, wy + wh·offset-frac)`).
    ///   cw, ch         — chip size.
    ///   padding        — clearance required around the chip on all sides.
    ///
    /// Walk on-screen windows front-to-back (z-ordered by
    /// `CGWindowListCopyWindowInfo`) and collect the rects of windows
    /// in front of the target. Target's visible region = window rect ∖
    /// ⋃ occluders, as disjoint axis-aligned fragments. Prefer the
    /// natural origin when its padded chip rect fits cleanly in some
    /// fragment; otherwise relocate to the top-left-most fragment that
    /// can host the chip.
    ///
    /// Occluder collection mirrors `window-visible-at?` to stay
    /// consistent with how visibility is judged elsewhere:
    ///   • Skip Modaliser's own panels.
    ///   • Stop at the target — match by `kCGWindowNumber` first, then
    ///     fall back to owner pid (`_AXUIElementGetWindow` disagrees
    ///     with CGWindowList for some apps; see the comment block in
    ///     `windowVisibleAtFunction`). Same-app windows count as the
    ///     target, not as occluders.
    ///   • Skip translucent overlays (alpha < 1.0).
    ///
    /// If the target isn't found in the on-screen list, we treat the
    /// window as unoccluded — same bias-to-visible policy
    /// `windowVisibleAtFunction` uses on empty info.
    private func findChipPositionFunction(_ args: Arguments) throws -> Expr {
        guard args.count == 11 else {
            throw RuntimeError.argumentCount(num: 11, args: .makeList(args))
        }
        let a = Array(args)
        let wid = try a[0].asInt64()
        let pid = try a[1].asInt64()
        let wx = CGFloat(try a[2].asInt64())
        let wy = CGFloat(try a[3].asInt64())
        let ww = CGFloat(try a[4].asInt64())
        let wh = CGFloat(try a[5].asInt64())
        let nx = CGFloat(try a[6].asInt64())
        let ny = CGFloat(try a[7].asInt64())
        let cw = CGFloat(try a[8].asInt64())
        let ch = CGFloat(try a[9].asInt64())
        let padding = CGFloat(try a[10].asInt64())

        let occluders = collectOccluderRects(targetWid: wid, targetPid: pid)
        guard let pos = ChipPlacement.chipPosition(
            windowRect: CGRect(x: wx, y: wy, width: ww, height: wh),
            occluders: occluders,
            naturalOrigin: CGPoint(x: nx, y: ny),
            chipSize: CGSize(width: cw, height: ch),
            padding: padding
        ) else {
            return .false
        }
        return SchemeAlistLookup.makeAlist([
            ("x", .fixnum(Int64(pos.x))),
            ("y", .fixnum(Int64(pos.y))),
        ], symbols: self.context.symbols)
    }

    /// Walk `CGWindowListCopyWindowInfo` (front-to-back z-order) and
    /// collect the rects of windows in front of the target. Stops at
    /// the first wid- or pid-match. See `findChipPositionFunction`
    /// docstring for the matching/skip rules.
    private func collectOccluderRects(targetWid: Int64, targetPid: Int64) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return []
        }
        let myPID = Int64(ProcessInfo.processInfo.processIdentifier)
        var occluders: [CGRect] = []
        for entry in list {
            let entryWid = (entry[kCGWindowNumber as String] as? NSNumber)?.int64Value ?? 0
            let entryPid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int64Value ?? 0

            if entryPid == myPID { continue }
            // Hit the target — everything before is in front, stop.
            if targetWid > 0 && entryWid == targetWid { return occluders }
            if targetPid > 0 && entryPid == targetPid { return occluders }

            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha < 1.0 { continue }

            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let bx = (bounds["X"] as? NSNumber)?.doubleValue,
                  let by = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let bw = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let bh = (bounds["Height"] as? NSNumber)?.doubleValue
            else { continue }
            occluders.append(CGRect(x: bx, y: by, width: bw, height: bh))
        }
        // Target not in list — no occluders established. Caller will
        // see the natural origin returned, matching `window-visible-at?`'s
        // bias-to-visible on missing info.
        return []
    }

    // MARK: - Helpers

    private func makeWindowAlist(_ window: WindowInfo) -> Expr {
        SchemeAlistLookup.makeAlist([
            ("text", .makeString(window.title)),
            ("subText", .makeString(window.ownerName)),
            ("icon", .makeString(window.bundleId)),
            ("iconType", .makeString("bundleId")),
            ("windowId", .fixnum(Int64(window.windowId))),
            ("ownerPid", .fixnum(Int64(window.ownerPID))),
        ], symbols: self.context.symbols)
    }

    private func makeCurrentSpaceWindowAlist(_ window: WindowInfo) -> Expr {
        SchemeAlistLookup.makeAlist([
            ("text", .makeString(window.title)),
            ("subText", .makeString(window.ownerName)),
            ("icon", .makeString(window.bundleId)),
            ("iconType", .makeString("bundleId")),
            ("windowId", .fixnum(Int64(window.windowId))),
            ("ownerPid", .fixnum(Int64(window.ownerPID))),
            ("x", .fixnum(Int64(window.bounds.origin.x))),
            ("y", .fixnum(Int64(window.bounds.origin.y))),
            ("w", .fixnum(Int64(window.bounds.size.width))),
            ("h", .fixnum(Int64(window.bounds.size.height))),
        ], symbols: self.context.symbols)
    }
}
