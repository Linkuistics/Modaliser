import Foundation
import Testing
@testable import Modaliser

/// Grove `window-chips-overlap-same-app-windows`, leaf 020/010 — Stage A:
/// same-app occluder collection (Cause 1 / ADR-0009).
///
/// Leaf 010 (now retired) *confirmed* the cause: `collectOccluderRects` stopped
/// at the first same-PID window, so a same-app back window got an EMPTY occluder
/// list, was judged unoccluded, and kept its natural top-left — landing on the
/// front window's chip. This suite verifies the fix: the pure
/// `ChipPlacement.occluderRects` now treats same-app front windows as occluders
/// like any other, stopping only at the *actual target* (by `wid`, else by rect
/// match among same-PID candidates). The collected occluders then flow through
/// the real `ChipPlacement.chipPosition`, relocating the back chip off the
/// colliding corner.
///
/// Stage B (the cross-chip invariant + lattice cascade for fully-occluded
/// windows) is leaf 020/020 — a window that flips to `chipPosition == nil` here
/// is *expected* and is its concern, not this suite's.
@Suite("Same-app window-chip collision — Stage A occluder collection (grove 020/010)")
struct SameAppChipCollisionTests {

    // Real chip constants from (modaliser theming): host-pad 12, chip 88×88.
    static let hostPad: CGFloat = 12
    static let chipSide: CGFloat = 56 + 2 * 16   // font-size + 2·padding = 88
    static var chipSize: CGSize { CGSize(width: chipSide, height: chipSide) }

    /// Natural chip origin exactly as `window-chip-for` computes it.
    static func naturalOrigin(of window: CGRect) -> CGPoint {
        CGPoint(x: window.minX + hostPad, y: window.minY + hostPad)
    }

    /// Chip rect at a placement point, matching `chips-overlap?`'s rect model.
    static func chipRect(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: chipSize)
    }

    /// The exact overlap predicate `chips-overlap?` uses in window-list.sld
    /// (strict inequalities; touching edges do not count as overlap).
    static func chipsOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// Build a synthetic on-screen window entry (front-to-back lists are
    /// written front-first, matching `CGWindowListCopyWindowInfo` order).
    static func entry(wid: Int64, pid: Int64, rect: CGRect,
                      alpha: Double = 1.0) -> ChipPlacement.WindowEntry {
        ChipPlacement.WindowEntry(wid: wid, pid: pid, alpha: alpha, rect: rect)
    }

    static let appPid: Int64 = 100
    static let selfPid: Int64 = 999_999

    /// THE FIX. A smaller front window F sits on the top-left of a larger
    /// same-app window B behind it (two iTerm windows; the reported case).
    /// `occluderRects` for B now returns `[F]` — the front same-app window is
    /// an occluder — where the buggy walk returned `[]` (it bailed on the first
    /// same-PID entry). The front window F, being frontmost, still gets `[]`.
    @Test func sameAppBackWindowCollectsFrontAsOccluder() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let back  = CGRect(x: 200, y: 150, width: 1200, height: 800)
        // z-order front-to-back: F (wid 1) over B (wid 2), same app.
        let list = [
            Self.entry(wid: 1, pid: Self.appPid, rect: front),
            Self.entry(wid: 2, pid: Self.appPid, rect: back),
        ]

        let backOccluders = ChipPlacement.occluderRects(
            in: list, targetWid: 2, targetPid: Self.appPid,
            targetRect: back, selfPid: Self.selfPid)
        let frontOccluders = ChipPlacement.occluderRects(
            in: list, targetWid: 1, targetPid: Self.appPid,
            targetRect: front, selfPid: Self.selfPid)

        #expect(backOccluders == [front])   // was [] under the bug
        #expect(frontOccluders == [])        // frontmost: nothing in front
    }

    /// END TO END. Feed the *collected* occluders (not a hand-written list)
    /// into the real `ChipPlacement.chipPosition`: B's chip relocates off the
    /// natural corner and the two chips no longer overlap. This is the whole
    /// Stage-A path the live pipeline runs, minus the live window-server read.
    @Test func collectedOccludersRelocateBackChip_noOverlap() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let back  = CGRect(x: 200, y: 150, width: 1200, height: 800)
        let list = [
            Self.entry(wid: 1, pid: Self.appPid, rect: front),
            Self.entry(wid: 2, pid: Self.appPid, rect: back),
        ]

        let frontPlaced = ChipPlacement.chipPosition(
            windowRect: front,
            occluders: ChipPlacement.occluderRects(
                in: list, targetWid: 1, targetPid: Self.appPid,
                targetRect: front, selfPid: Self.selfPid),
            naturalOrigin: Self.naturalOrigin(of: front),
            chipSize: Self.chipSize, padding: Self.hostPad)
        let backPlaced = ChipPlacement.chipPosition(
            windowRect: back,
            occluders: ChipPlacement.occluderRects(
                in: list, targetWid: 2, targetPid: Self.appPid,
                targetRect: back, selfPid: Self.selfPid),
            naturalOrigin: Self.naturalOrigin(of: back),
            chipSize: Self.chipSize, padding: Self.hostPad)

        let f = try! #require(frontPlaced)
        let b = try! #require(backPlaced)
        #expect(b != Self.naturalOrigin(of: back))   // moved off the colliding corner
        #expect(!Self.chipsOverlap(Self.chipRect(at: f), Self.chipRect(at: b)))
    }

    /// WID FALLBACK. When `_AXUIElementGetWindow`'s `wid` matches no
    /// `kCGWindowNumber` (the disagreement ADR-0009 calls out), the target is
    /// still found by rect among same-PID candidates, so the front same-app
    /// window is collected as an occluder.
    @Test func unreliableWid_fallsBackToRectMatch() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let back  = CGRect(x: 200, y: 150, width: 1200, height: 800)
        let list = [
            Self.entry(wid: 1, pid: Self.appPid, rect: front),
            Self.entry(wid: 2, pid: Self.appPid, rect: back),
        ]

        // targetWid 777 is in NO entry — wid lookup fails, rect match wins.
        let occluders = ChipPlacement.occluderRects(
            in: list, targetWid: 777, targetPid: Self.appPid,
            targetRect: back, selfPid: Self.selfPid)
        #expect(occluders == [front])
    }

    /// Rect match absorbs sub-tolerance rounding between the integer target
    /// rect and CGWindowList's double bounds.
    @Test func rectMatchToleratesRounding() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let backDoubles = CGRect(x: 200.6, y: 149.4, width: 1199.5, height: 800.4)
        let list = [
            Self.entry(wid: 1, pid: Self.appPid, rect: front),
            Self.entry(wid: 2, pid: Self.appPid, rect: backDoubles),
        ]
        // Target rect is the integer-snapped version the AX side carries.
        let occluders = ChipPlacement.occluderRects(
            in: list, targetWid: 0, targetPid: Self.appPid,
            targetRect: CGRect(x: 200, y: 150, width: 1200, height: 800),
            selfPid: Self.selfPid)
        #expect(occluders == [front])
    }

    /// BIAS TO VISIBLE. If neither `wid` nor rect resolves the target (it is
    /// absent from the on-screen list), no occluders are established — the
    /// chip keeps its natural corner rather than relocating needlessly.
    @Test func targetAbsent_biasesToVisible() {
        let other = CGRect(x: 0, y: 0, width: 300, height: 300)
        let list = [Self.entry(wid: 1, pid: 42, rect: other)]
        let occluders = ChipPlacement.occluderRects(
            in: list, targetWid: 2, targetPid: Self.appPid,
            targetRect: CGRect(x: 200, y: 150, width: 1200, height: 800),
            selfPid: Self.selfPid)
        #expect(occluders == [])
    }

    /// SKIP RULES preserved. Modaliser's own panels (`selfPid`) and translucent
    /// overlays (alpha < 1.0, e.g. HazeOver) in front of the target are not
    /// collected as occluders; an opaque foreign window is.
    @Test func skipsOwnPanelsAndTranslucentOverlays() {
        let target = CGRect(x: 200, y: 150, width: 800, height: 600)
        let ownPanel = CGRect(x: 0, y: 0, width: 88, height: 88)
        let dimmer = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let opaqueForeign = CGRect(x: 220, y: 170, width: 200, height: 150)
        let list = [
            Self.entry(wid: 10, pid: Self.selfPid, rect: ownPanel),         // skipped: our panel
            Self.entry(wid: 11, pid: 50, rect: dimmer, alpha: 0.3),         // skipped: translucent
            Self.entry(wid: 12, pid: 50, rect: opaqueForeign),             // collected
            Self.entry(wid: 99, pid: Self.appPid, rect: target),           // target
        ]
        let occluders = ChipPlacement.occluderRects(
            in: list, targetWid: 99, targetPid: Self.appPid,
            targetRect: target, selfPid: Self.selfPid)
        #expect(occluders == [opaqueForeign])
    }

    /// CLASSIFICATION FLIP (Stage-A → Stage-B handoff). Two fully-stacked
    /// identical same-app frames with distinct wids: the back window's
    /// collected occluder is the front frame, which fully covers it, so
    /// `chipPosition` returns nil — the "no usable area" verdict Stage B's
    /// cascade consumes. The front window stays visible at its natural corner.
    @Test func fullyStackedFrames_backFlipsToNoUsableArea() {
        let frame = CGRect(x: 300, y: 250, width: 900, height: 600)
        let list = [
            Self.entry(wid: 1, pid: Self.appPid, rect: frame),   // front
            Self.entry(wid: 2, pid: Self.appPid, rect: frame),   // back, identical
        ]
        let natural = Self.naturalOrigin(of: frame)

        let front = ChipPlacement.chipPosition(
            windowRect: frame,
            occluders: ChipPlacement.occluderRects(
                in: list, targetWid: 1, targetPid: Self.appPid,
                targetRect: frame, selfPid: Self.selfPid),
            naturalOrigin: natural, chipSize: Self.chipSize, padding: Self.hostPad)
        let back = ChipPlacement.chipPosition(
            windowRect: frame,
            occluders: ChipPlacement.occluderRects(
                in: list, targetWid: 2, targetPid: Self.appPid,
                targetRect: frame, selfPid: Self.selfPid),
            naturalOrigin: natural, chipSize: Self.chipSize, padding: Self.hostPad)

        #expect(front == natural)   // frontmost: on-window chip at natural corner
        #expect(back == nil)        // fully covered: no usable area → Stage B cascade
    }
}
