import Testing
import AppKit
import LispKit
@testable import Modaliser

@Suite("CursorColor")
struct CursorColorTests {
    @Test func parsesSixDigitHex() throws {
        let c = try #require(CursorColor.parse("#FF0000")?.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - 1.0) < 0.01)
        #expect(abs(c.greenComponent - 0.0) < 0.01)
        #expect(abs(c.blueComponent - 0.0) < 0.01)
    }

    @Test func parsesThreeDigitHexWithoutHash() throws {
        let c = try #require(CursorColor.parse("0f0")?.usingColorSpace(.sRGB))
        #expect(abs(c.greenComponent - 1.0) < 0.01)
        #expect(abs(c.redComponent - 0.0) < 0.01)
    }

    @Test func rejectsInvalidInput() {
        #expect(CursorColor.parse("zzz") == nil)
        #expect(CursorColor.parse("#12") == nil)
        #expect(CursorColor.parse("") == nil)
    }
}

@Suite("CursorHighlightOptions")
struct CursorHighlightOptionsTests {
    @Test func appliesDefaultsWhenEmpty() {
        let o = CursorHighlightOptions.from([])
        #expect(o.size == 240)
        #expect(o.thickness == 6)
        #expect(o.glow == 18)
        #expect(abs(o.duration - 0.45) < 0.0001)
        #expect(o.nudge == true)
    }

    @Test func overridesNumbersFromFixnumAndFlonum() {
        let o = CursorHighlightOptions.from([
            ("size", .fixnum(300)),
            ("duration", .flonum(0.8)),
            ("glow", .fixnum(30)),
        ])
        #expect(o.size == 300)
        #expect(o.glow == 30)
        #expect(abs(o.duration - 0.8) < 0.0001)
    }

    @Test func nudgeFalseDisablesNudge() {
        #expect(CursorHighlightOptions.from([("nudge", .false)]).nudge == false)
        #expect(CursorHighlightOptions.from([("nudge", .true)]).nudge == true)
    }

    @Test func ignoresUnknownKeywords() {
        let o = CursorHighlightOptions.from([("bogus", .fixnum(1))])
        #expect(o.size == 240)
    }

    @Test func appliesColourOverride() throws {
        let o = CursorHighlightOptions.from([("color", .makeString("#FF0000"))])
        let c = try #require(o.color.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - 1.0) < 0.01)
    }

    @Test func keepsDefaultColourOnInvalidHex() throws {
        let dflt = try #require(CursorHighlightOptions.from([]).color.usingColorSpace(.sRGB))
        let o = try #require(CursorHighlightOptions.from([("color", .makeString("nope"))]).color.usingColorSpace(.sRGB))
        #expect(abs(o.redComponent - dflt.redComponent) < 0.01)
        #expect(abs(o.greenComponent - dflt.greenComponent) < 0.01)
        #expect(abs(o.blueComponent - dflt.blueComponent) < 0.01)
    }
}
