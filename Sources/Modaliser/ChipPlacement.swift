import CoreGraphics

/// Pure geometric helpers for window-chip placement.
///
/// Background: window chips are painted at a window's top-left by default,
/// but the top-left may be covered by a window in front. The painter's-
/// algorithm view is "build an occlusion map by walking windows back-to-
/// front, then ask per window: where is there a chip-sized clear patch?"
/// In our case the clear patch can always be expressed as a union of
/// axis-aligned rectangles (window rect minus the union of front-er
/// window rects), so we don't need a quadtree — direct rectangle set-
/// difference produces the same fragments a quadtree's leaves would.
///
/// Coordinate convention: AX top-left origin (y increases downward),
/// matching `WindowLibrary.listCurrentSpaceWindows` and the chip
/// coordinate space.
enum ChipPlacement {

    /// One on-screen window as occluder collection sees it: its
    /// CoreGraphics window number (`wid`), owner pid, alpha, and AX-origin
    /// bounds. `rect` is nil when `CGWindowListCopyWindowInfo` omitted
    /// usable bounds. A plain value type so `occluderRects` can be unit
    /// tested with a synthetic z-ordered list, no live window server.
    struct WindowEntry {
        let wid: Int64
        let pid: Int64
        let alpha: Double
        let rect: CGRect?
    }

    /// Rect-match tolerance (points) for disambiguating the target among
    /// same-app windows when `wid` is unreliable. CGWindowList bounds are
    /// doubles; the target rect arrives as integers, so a couple of points
    /// of slop absorbs rounding without admitting a genuinely different
    /// window.
    static let occluderRectTolerance: CGFloat = 2

    /// Collect the rects of windows in front of the target, given the
    /// on-screen window list in `CGWindowListCopyWindowInfo` front-to-back
    /// z-order. Pure — no system calls — so it is unit-testable.
    ///
    /// The walk stops at the *actual target*, located in two phases:
    ///   • by `wid` — when `targetWid > 0` and some entry carries that
    ///     CoreGraphics window number; else
    ///   • by rect — the first same-pid entry whose bounds match
    ///     `targetRect` within `occluderRectTolerance`. This fallback
    ///     exists because `_AXUIElementGetWindow` (which fills the target's
    ///     `wid`) and `kCGWindowNumber` disagree for some apps, making
    ///     `wid` an unreliable key (see `windowVisibleAtFunction`).
    /// If neither resolves the target, returns `[]` — bias to visible,
    /// rather than over-collecting and relocating a chip that need not move.
    ///
    /// Every window in front of the target — *including same-app windows*
    /// (ADR-0009) — counts as an occluder, except Modaliser's own panels
    /// (`selfPid`) and translucent overlays (alpha < 1.0, e.g. HazeOver).
    ///
    /// Locating the target index *before* collecting (rather than a
    /// per-entry stop test) is what lets the rect fallback coexist safely
    /// with reliable `wid`: a same-app occluder that happens to share the
    /// target's frame cannot end the walk early when `wid` already found
    /// the target.
    ///
    /// Limitation: when `wid` is unreliable *and* several same-app windows
    /// share an identical frame (the fully-stacked worst case), rect-match
    /// cannot tell them apart and stops at the frontmost — under-counting a
    /// rear target's occluders. Stage B's lattice cascade keeps such a
    /// window selectable regardless; on real displays `wid` is reliable
    /// enough that distinct windows are matched exactly.
    static func occluderRects(
        in windows: [WindowEntry],
        targetWid: Int64,
        targetPid: Int64,
        targetRect: CGRect,
        selfPid: Int64
    ) -> [CGRect] {
        // Phase 1 — locate the target's index in z-order.
        var targetIndex: Int?
        if targetWid > 0 {
            targetIndex = windows.firstIndex {
                $0.pid != selfPid && $0.wid == targetWid
            }
        }
        if targetIndex == nil && targetPid > 0 {
            targetIndex = windows.firstIndex { entry in
                entry.pid == targetPid
                    && entry.pid != selfPid
                    && (entry.rect.map { rectsMatch($0, targetRect) } ?? false)
            }
        }
        guard let stop = targetIndex else { return [] }

        // Phase 2 — every opaque, non-self window in front of the target.
        var occluders: [CGRect] = []
        for entry in windows[..<stop] {
            if entry.pid == selfPid { continue }
            if entry.alpha < 1.0 { continue }
            guard let rect = entry.rect else { continue }
            occluders.append(rect)
        }
        return occluders
    }

    /// Whether two rects coincide within `occluderRectTolerance` on every
    /// edge — used to recognise the target among same-app windows.
    private static func rectsMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= occluderRectTolerance
            && abs(a.minY - b.minY) <= occluderRectTolerance
            && abs(a.width - b.width) <= occluderRectTolerance
            && abs(a.height - b.height) <= occluderRectTolerance
    }

    /// Returns the disjoint axis-aligned rectangles covering
    /// `minuend \ subtrahend`. Yields 0–4 rectangles:
    ///   • 0 when `subtrahend` fully contains `minuend`,
    ///   • 1 when `subtrahend` clips one edge,
    ///   • 2 when `subtrahend` clips a corner,
    ///   • 3 when `subtrahend` clips a strip across one axis,
    ///   • 4 when `subtrahend` sits strictly inside `minuend`.
    ///
    /// When `subtrahend` doesn't intersect `minuend`, returns `[minuend]`
    /// unchanged.
    static func subtract(_ minuend: CGRect, _ subtrahend: CGRect) -> [CGRect] {
        let ix1 = max(minuend.minX, subtrahend.minX)
        let iy1 = max(minuend.minY, subtrahend.minY)
        let ix2 = min(minuend.maxX, subtrahend.maxX)
        let iy2 = min(minuend.maxY, subtrahend.maxY)
        if ix1 >= ix2 || iy1 >= iy2 { return [minuend] }

        var result: [CGRect] = []
        // Top strip — minuend above the intersection.
        if minuend.minY < iy1 {
            result.append(CGRect(x: minuend.minX, y: minuend.minY,
                                 width: minuend.width,
                                 height: iy1 - minuend.minY))
        }
        // Bottom strip — minuend below the intersection.
        if iy2 < minuend.maxY {
            result.append(CGRect(x: minuend.minX, y: iy2,
                                 width: minuend.width,
                                 height: minuend.maxY - iy2))
        }
        // Left strip — within the intersection's y-band, to the left.
        if minuend.minX < ix1 {
            result.append(CGRect(x: minuend.minX, y: iy1,
                                 width: ix1 - minuend.minX,
                                 height: iy2 - iy1))
        }
        // Right strip — within the intersection's y-band, to the right.
        if ix2 < minuend.maxX {
            result.append(CGRect(x: ix2, y: iy1,
                                 width: minuend.maxX - ix2,
                                 height: iy2 - iy1))
        }
        return result
    }

    /// Iteratively subtract each rect in `subtrahends` from `minuend`,
    /// re-fragmenting as needed. Fragments are guaranteed pairwise
    /// disjoint and to not intersect any subtrahend.
    static func subtractAll(_ minuend: CGRect, _ subtrahends: [CGRect]) -> [CGRect] {
        var current: [CGRect] = [minuend]
        for sub in subtrahends {
            var next: [CGRect] = []
            for frag in current {
                next.append(contentsOf: subtract(frag, sub))
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    /// Decide where to place a chip on a window, preferring the
    /// configured natural origin when it fits cleanly within a visible
    /// fragment, otherwise relocating to the top-left-most fragment
    /// that can host the chip.
    ///
    /// "Fits cleanly" means the chip rect at `naturalOrigin` inflated by
    /// `padding` on all sides is fully contained in some visible
    /// fragment (no occluder edge crosses through the padded chip).
    ///
    /// Returns nil when no fragment can host the chip — the caller then
    /// falls back to faded/relocated rendering.
    static func chipPosition(
        windowRect: CGRect,
        occluders: [CGRect],
        naturalOrigin: CGPoint,
        chipSize: CGSize,
        padding: CGFloat
    ) -> CGPoint? {
        let fragments = subtractAll(windowRect, occluders)
        let requiredAtNatural = CGRect(
            x: naturalOrigin.x - padding,
            y: naturalOrigin.y - padding,
            width: chipSize.width + 2 * padding,
            height: chipSize.height + 2 * padding)
        for frag in fragments {
            if frag.contains(requiredAtNatural) {
                return naturalOrigin
            }
        }
        return topLeftChipPosition(in: fragments, chipSize: chipSize, padding: padding)
    }

    /// Pick the top-left-most chip placement among `fragments`. A
    /// fragment qualifies iff it can host a `chipSize` rect with
    /// `padding` margin on all sides — i.e. width ≥ chipSize.width
    /// + 2·padding and height ≥ chipSize.height + 2·padding. The
    /// returned point is the chip's top-left, set to the qualifying
    /// fragment's origin offset by `(padding, padding)`.
    ///
    /// "Top-left-most" is the lexicographic minimum of (minY, minX) —
    /// preferring fragments closer to the top, breaking ties by
    /// preferring leftmost.
    static func topLeftChipPosition(
        in fragments: [CGRect],
        chipSize: CGSize,
        padding: CGFloat
    ) -> CGPoint? {
        let requiredW = chipSize.width + 2 * padding
        let requiredH = chipSize.height + 2 * padding
        var best: CGRect?
        for frag in fragments {
            guard frag.width >= requiredW, frag.height >= requiredH else { continue }
            if let b = best {
                if frag.minY < b.minY || (frag.minY == b.minY && frag.minX < b.minX) {
                    best = frag
                }
            } else {
                best = frag
            }
        }
        guard let chosen = best else { return nil }
        return CGPoint(x: chosen.minX + padding, y: chosen.minY + padding)
    }
}
