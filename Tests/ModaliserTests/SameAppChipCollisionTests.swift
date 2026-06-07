import Foundation
import Testing
@testable import Modaliser

/// Grove `window-chips-overlap-same-app-windows`, leaf 010 — reproduce the
/// same-app overlapping-window chip collision and pin its cause on real code.
///
/// This is a *characterization* / diagnosis suite, not a fix. It exercises the
/// real production geometry (`ChipPlacement`) with the exact inputs each chip
/// gets in the live pipeline, and shows the collision is caused by
/// `WindowLibrary.collectOccluderRects` handing a same-app back window an
/// EMPTY occluder list. The contrasting "correct occluders" cases show the
/// fix direction (leaf 020 owns the actual design).
///
/// Live pipeline recap (verified by reading window-list.sld + WindowLibrary.swift):
///   1. `window-chip-for` puts each chip at the window's top-left:
///        natural origin = (wx + host-pad, wy + host-pad), host-pad = 12.
///      chip size = font-size(56) + 2·padding(16) = 88×88.
///   2. `find-chip-position` → `collectOccluderRects(targetWid, targetPid)`
///      walks CGWindowList front-to-back and RETURNS on the first same-PID
///      entry (WindowLibrary.swift). For a back window of the same app, the
///      front same-app window is that first entry → occluders = [] → the back
///      window is judged unoccluded.
///   3. `ChipPlacement.chipPosition` with occluders=[] keeps the natural
///      origin → back chip lands on the front chip. Both are classified
///      *visible* (#t), and the Scheme dodge `resolve-occluded-against-visible`
///      only relocates *occluded* (#f) chips — so the overlap is never undone.
@Suite("Same-app window-chip collision — cause confirmation (grove 010)")
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

    /// SYMPTOM. A smaller front window F sits on the top-left of a larger
    /// same-app window B behind it (two iTerm windows; the reported case).
    /// With the empty occluder list `collectOccluderRects` hands B today,
    /// the real `ChipPlacement.chipPosition` keeps B's chip at its natural
    /// top-left — identical to F's chip → the two chips coincide exactly.
    @Test func sameAppBackWindowGetsEmptyOccluders_chipsCoincide() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let back  = CGRect(x: 200, y: 150, width: 1200, height: 800)

        let frontNatural = Self.naturalOrigin(of: front)
        let backNatural  = Self.naturalOrigin(of: back)

        // Front window: collectOccluderRects returns [] (it's frontmost).
        let frontPlaced = ChipPlacement.chipPosition(
            windowRect: front, occluders: [],
            naturalOrigin: frontNatural, chipSize: Self.chipSize, padding: Self.hostPad)

        // Back window: collectOccluderRects ALSO returns [] — it hit the
        // front same-app window first and bailed (the bug under test).
        let backPlaced = ChipPlacement.chipPosition(
            windowRect: back, occluders: [],
            naturalOrigin: backNatural, chipSize: Self.chipSize, padding: Self.hostPad)

        print("[grove-010] BUGGY same-app input (occluders=[] for both):")
        print("  front window \(front) -> chip \(frontPlaced as Any)")
        print("  back  window \(back)  -> chip \(backPlaced as Any)")

        let f = try! #require(frontPlaced)
        let b = try! #require(backPlaced)
        let fRect = Self.chipRect(at: f)
        let bRect = Self.chipRect(at: b)
        print("  front chip rect \(fRect)")
        print("  back  chip rect \(bRect)")
        print("  overlap? \(Self.chipsOverlap(fRect, bRect))")

        // Both chips stay at the identical natural top-left → exact collision.
        #expect(b == backNatural)
        #expect(b == f)
        #expect(Self.chipsOverlap(fRect, bRect))
    }

    /// CAUSE PINNED. Same windows, but feed B the occluder list a correct
    /// `collectOccluderRects` WOULD return — [front]. The real geometry now
    /// relocates B's chip to the next clear fragment, and the two chips no
    /// longer overlap. The only thing that changed is the occluder list, so
    /// the empty-list early-return is the cause.
    @Test func correctOccludersRelocateBackChip_noOverlap() {
        let front = CGRect(x: 200, y: 150, width: 500, height: 400)
        let back  = CGRect(x: 200, y: 150, width: 1200, height: 800)

        let frontNatural = Self.naturalOrigin(of: front)
        let backNatural  = Self.naturalOrigin(of: back)

        let frontPlaced = ChipPlacement.chipPosition(
            windowRect: front, occluders: [],
            naturalOrigin: frontNatural, chipSize: Self.chipSize, padding: Self.hostPad)
        // The fix-direction input: the front same-app window IS an occluder.
        let backPlaced = ChipPlacement.chipPosition(
            windowRect: back, occluders: [front],
            naturalOrigin: backNatural, chipSize: Self.chipSize, padding: Self.hostPad)

        print("[grove-010] CORRECT input (occluders=[front] for back):")
        print("  front chip -> \(frontPlaced as Any)")
        print("  back  chip -> \(backPlaced as Any)  (relocated off the natural corner)")

        let f = try! #require(frontPlaced)
        let b = try! #require(backPlaced)
        #expect(b != backNatural)               // it moved off the colliding corner
        #expect(!Self.chipsOverlap(Self.chipRect(at: f), Self.chipRect(at: b)))
    }

    /// CLASSIFICATION FLIP. Two fully-stacked identical same-app frames.
    /// Buggy input ([]) → chipPosition is non-nil → the back window is
    /// classified *visible* and never enters the dodge. Correct input
    /// ([front]) → fully covered → chipPosition is nil → it would be
    /// classified *occluded* and routed to `resolve-occluded-against-visible`.
    /// This is why the second (Scheme) stage doesn't save us today: the back
    /// chip is mislabelled visible, and the dodge only moves occluded chips.
    @Test func fullyStackedFrames_classificationFlipsWithCorrectOccluders() {
        let frame = CGRect(x: 300, y: 250, width: 900, height: 600)
        let natural = Self.naturalOrigin(of: frame)

        let buggy = ChipPlacement.chipPosition(
            windowRect: frame, occluders: [],
            naturalOrigin: natural, chipSize: Self.chipSize, padding: Self.hostPad)
        let correct = ChipPlacement.chipPosition(
            windowRect: frame, occluders: [frame],
            naturalOrigin: natural, chipSize: Self.chipSize, padding: Self.hostPad)

        print("[grove-010] fully-stacked identical frames:")
        print("  buggy   occluders=[]      -> \(buggy as Any)  (classified VISIBLE, skips dodge)")
        print("  correct occluders=[frame] -> \(correct as Any)  (classified OCCLUDED, enters dodge)")

        #expect(buggy == natural)   // visible at natural corner — the collision
        #expect(correct == nil)     // occluded — would be routed to the dodge
    }
}
