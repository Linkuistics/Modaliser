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
