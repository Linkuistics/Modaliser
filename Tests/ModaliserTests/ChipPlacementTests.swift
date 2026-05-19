import Foundation
import Testing
@testable import Modaliser

@Suite("ChipPlacement — rect subtraction + top-left chip slot")
struct ChipPlacementTests {

    // MARK: - subtract(_:_:)
    // Rectangle set-difference returns 0-4 axis-aligned disjoint strips
    // that together cover (minuend \ subtrahend).

    @Test func subtractNoIntersectionReturnsMinuend() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 200, y: 200, width: 50, height: 50)
        #expect(ChipPlacement.subtract(a, b) == [a])
    }

    @Test func subtractFullyCoveredReturnsEmpty() {
        let a = CGRect(x: 10, y: 10, width: 50, height: 50)
        let b = CGRect(x: 0, y: 0, width: 200, height: 200)
        #expect(ChipPlacement.subtract(a, b).isEmpty)
    }

    @Test func subtractIdenticalReturnsEmpty() {
        let a = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(ChipPlacement.subtract(a, a).isEmpty)
    }

    @Test func subtractTopLeftCornerYieldsTwoStrips() {
        // B covers A's top-left quadrant. Visible: an L-shape decomposed
        // into a bottom strip (full width) and a right strip (middle band).
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 0, y: 0, width: 40, height: 30)
        let result = ChipPlacement.subtract(a, b)
        // No top strip (b touches a's top), no left strip (b touches a's left).
        // Expect bottom (y=30, full width 100, height 70) and right (x=40, y=0, width 60, height 30).
        #expect(result.contains(CGRect(x: 0, y: 30, width: 100, height: 70)))
        #expect(result.contains(CGRect(x: 40, y: 0, width: 60, height: 30)))
        #expect(result.count == 2)
        // No overlap between fragments.
        #expect(!result[0].intersects(result[1]))
    }

    @Test func subtractInteriorYieldsFourStrips() {
        // B sits strictly inside A → top, bottom, left, right strips.
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 25, y: 25, width: 50, height: 50)
        let result = ChipPlacement.subtract(a, b)
        #expect(result.count == 4)
        // Total area of strips = area(A) - area(B) = 10000 - 2500 = 7500.
        let totalArea = result.reduce(0.0) { $0 + $1.width * $1.height }
        #expect(totalArea == 7500)
        // All strips disjoint pairwise.
        for i in 0..<result.count {
            for j in (i+1)..<result.count {
                #expect(!result[i].intersects(result[j]))
            }
        }
    }

    @Test func subtractTopHalfLeavesBottomStrip() {
        // B covers A's entire top half. Visible: single rect, the bottom half.
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        let b = CGRect(x: 0, y: 0, width: 200, height: 60)  // covers y=10..60 of A
        let result = ChipPlacement.subtract(a, b)
        #expect(result == [CGRect(x: 10, y: 60, width: 100, height: 50)])
    }

    @Test func subtractZeroAreaSubtrahendReturnsMinuend() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 50, y: 50, width: 0, height: 0)
        #expect(ChipPlacement.subtract(a, b) == [a])
    }

    // MARK: - subtractAll(_:_:)
    // Iteratively subtract a list of occluders. Used for "window rect
    // minus all front-er windows."

    @Test func subtractAllEmptyOccludersReturnsMinuend() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(ChipPlacement.subtractAll(a, []) == [a])
    }

    @Test func subtractAllTwoDisjointOccludersLeavesGap() {
        // A is 100×100. Two occluders cover the top-left and top-right
        // corners. Bottom half is fully visible, plus a middle gap on top.
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b1 = CGRect(x: 0, y: 0, width: 30, height: 30)
        let b2 = CGRect(x: 70, y: 0, width: 30, height: 30)
        let result = ChipPlacement.subtractAll(a, [b1, b2])
        // Result should cover everything in A except the two corners.
        // Total area = 10000 - 900 - 900 = 8200.
        let totalArea = result.reduce(0.0) { $0 + $1.width * $1.height }
        #expect(totalArea == 8200)
        // Result fragments are pairwise disjoint.
        for i in 0..<result.count {
            for j in (i+1)..<result.count {
                #expect(!result[i].intersects(result[j]))
            }
            // And none of them overlap either occluder.
            #expect(!result[i].intersects(b1))
            #expect(!result[i].intersects(b2))
        }
    }

    @Test func subtractAllStackedOccludersConverges() {
        // Defensive: subtracting the same rect twice shouldn't fragment
        // further than subtracting it once.
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 25, y: 25, width: 50, height: 50)
        let once = ChipPlacement.subtractAll(a, [b])
        let twice = ChipPlacement.subtractAll(a, [b, b])
        let onceArea = once.reduce(0.0) { $0 + $1.width * $1.height }
        let twiceArea = twice.reduce(0.0) { $0 + $1.width * $1.height }
        #expect(onceArea == twiceArea)
    }

    // MARK: - topLeftChipPosition

    @Test func topLeftChipPositionNoFragmentsReturnsNil() {
        let p = ChipPlacement.topLeftChipPosition(
            in: [], chipSize: CGSize(width: 20, height: 20), padding: 4)
        #expect(p == nil)
    }

    @Test func topLeftChipPositionFragmentTooSmallReturnsNil() {
        // Fragment is exactly chip-size with no room for padding.
        let frag = CGRect(x: 0, y: 0, width: 20, height: 20)
        let p = ChipPlacement.topLeftChipPosition(
            in: [frag], chipSize: CGSize(width: 20, height: 20), padding: 4)
        #expect(p == nil)
    }

    @Test func topLeftChipPositionTightFitReturnsPaddedOrigin() {
        // Fragment is exactly chip + 2·padding in each axis → fits, chip
        // lands at fragment.origin + (padding, padding).
        let frag = CGRect(x: 100, y: 50, width: 28, height: 28)
        let p = ChipPlacement.topLeftChipPosition(
            in: [frag], chipSize: CGSize(width: 20, height: 20), padding: 4)
        #expect(p == CGPoint(x: 104, y: 54))
    }

    @Test func topLeftChipPositionPicksMinYFragment() {
        // Two qualifying fragments — should pick the one with smaller y.
        let lower = CGRect(x: 0, y: 100, width: 200, height: 200)
        let upper = CGRect(x: 500, y: 50, width: 200, height: 200)
        let p = ChipPlacement.topLeftChipPosition(
            in: [lower, upper],
            chipSize: CGSize(width: 20, height: 20),
            padding: 4)
        #expect(p == CGPoint(x: 504, y: 54))
    }

    @Test func topLeftChipPositionTiesOnYBreaksByX() {
        // Two qualifying fragments at the same y — leftmost wins.
        let right = CGRect(x: 500, y: 50, width: 200, height: 200)
        let left  = CGRect(x: 100, y: 50, width: 200, height: 200)
        let p = ChipPlacement.topLeftChipPosition(
            in: [right, left],
            chipSize: CGSize(width: 20, height: 20),
            padding: 4)
        #expect(p == CGPoint(x: 104, y: 54))
    }

    @Test func topLeftChipPositionSkipsUnderSizedFragments() {
        // First fragment is too small; second qualifies. Algorithm must
        // not just pick "first acceptable in list order."
        let tooSmall = CGRect(x: 0, y: 0, width: 10, height: 200)   // smaller y but too narrow
        let big      = CGRect(x: 0, y: 100, width: 200, height: 200)
        let p = ChipPlacement.topLeftChipPosition(
            in: [tooSmall, big],
            chipSize: CGSize(width: 20, height: 20),
            padding: 4)
        #expect(p == CGPoint(x: 4, y: 104))
    }

    // MARK: - End-to-end: realistic window scenario

    @Test func windowOcclusionEndToEnd() {
        // Window W is 1000×800. A front-er window F covers W's top-left
        // 400×300. Result: chip should land at the top of the right
        // strip just past F's right edge, not in the bottom strip.
        let w = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = CGRect(x: 0, y: 0, width: 400, height: 300)
        let fragments = ChipPlacement.subtractAll(w, [f])
        let p = ChipPlacement.topLeftChipPosition(
            in: fragments,
            chipSize: CGSize(width: 24, height: 24),
            padding: 4)
        // Right strip starts at x=400, y=0; chip lands at (400+4, 0+4).
        #expect(p == CGPoint(x: 404, y: 4))
    }

    @Test func windowFullyOccludedReturnsNil() {
        let w = CGRect(x: 0, y: 0, width: 200, height: 200)
        let f = CGRect(x: 0, y: 0, width: 300, height: 300)
        let fragments = ChipPlacement.subtractAll(w, [f])
        #expect(fragments.isEmpty)
        let p = ChipPlacement.topLeftChipPosition(
            in: fragments,
            chipSize: CGSize(width: 20, height: 20),
            padding: 4)
        #expect(p == nil)
    }

    // MARK: - chipPosition (combined: prefer natural origin, fall back to top-left)

    @Test func chipPositionPrefersNaturalWhenFits() {
        // Unoccluded window — natural origin (chip at 2% inset) sits
        // safely inside the single fragment and should be honoured.
        let w = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let natural = CGPoint(x: 20, y: 16)
        let p = ChipPlacement.chipPosition(
            windowRect: w,
            occluders: [],
            naturalOrigin: natural,
            chipSize: CGSize(width: 24, height: 24),
            padding: 4)
        #expect(p == natural)
    }

    @Test func chipPositionRelocatesWhenNaturalOccluded() {
        // Front-er window covers the natural chip position — we must
        // relocate to the top-left of the next clear fragment.
        let w = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = CGRect(x: 0, y: 0, width: 400, height: 300)
        let natural = CGPoint(x: 20, y: 16)  // inside the occluder
        let p = ChipPlacement.chipPosition(
            windowRect: w,
            occluders: [f],
            naturalOrigin: natural,
            chipSize: CGSize(width: 24, height: 24),
            padding: 4)
        // Right strip starts at x=400, y=0.
        #expect(p == CGPoint(x: 404, y: 4))
    }

    @Test func chipPositionReturnsNilWhenNoFragmentFits() {
        // Window fully covered → no fragment, no placement.
        let w = CGRect(x: 0, y: 0, width: 200, height: 200)
        let f = CGRect(x: 0, y: 0, width: 300, height: 300)
        let p = ChipPlacement.chipPosition(
            windowRect: w,
            occluders: [f],
            naturalOrigin: CGPoint(x: 4, y: 4),
            chipSize: CGSize(width: 24, height: 24),
            padding: 4)
        #expect(p == nil)
    }

    @Test func chipPositionNaturalChipMustBeFullyInFragment() {
        // Natural origin is at (20, 16), chip is 24×24 with 4px padding —
        // required region is (16, 12)-(48, 44). Front-er covers (0,0)-(30,30)
        // → required region intersects it. Must relocate, not keep natural.
        let w = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = CGRect(x: 0, y: 0, width: 30, height: 30)
        let natural = CGPoint(x: 20, y: 16)
        let p = ChipPlacement.chipPosition(
            windowRect: w,
            occluders: [f],
            naturalOrigin: natural,
            chipSize: CGSize(width: 24, height: 24),
            padding: 4)
        // The natural origin alone is *outside* the 30×30 occluder, but
        // the inflated required region (16,12)-(48,44) crosses into it,
        // so we expect a relocation, not a kept-natural.
        #expect(p != natural)
    }
}
