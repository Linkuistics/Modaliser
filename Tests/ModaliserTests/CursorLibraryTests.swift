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
        let (o, warnings) = CursorHighlightOptions.parse([])
        #expect(o.size == 240)
        #expect(o.thickness == 6)
        #expect(o.glow == 18)
        #expect(abs(o.duration - 0.45) < 0.0001)
        #expect(o.nudge == true)
        #expect(warnings.isEmpty)
    }

    @Test func overridesNumbersFromFixnumAndFlonum() {
        let (o, warnings) = CursorHighlightOptions.parse([
            ("size", .fixnum(300)),
            ("duration", .flonum(0.8)),
            ("glow", .fixnum(30)),
        ])
        #expect(o.size == 300)
        #expect(o.glow == 30)
        #expect(abs(o.duration - 0.8) < 0.0001)
        #expect(warnings.isEmpty)
    }

    @Test func nudgeFalseDisablesNudge() {
        #expect(CursorHighlightOptions.parse([("nudge", .false)]).options.nudge == false)
        #expect(CursorHighlightOptions.parse([("nudge", .true)]).options.nudge == true)
    }

    @Test func appliesColourOverride() throws {
        let (o, warnings) = CursorHighlightOptions.parse([("color", .makeString("#FF0000"))])
        let c = try #require(o.color.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - 1.0) < 0.01)
        #expect(warnings.isEmpty)
    }

    @Test func keepsDefaultColourOnInvalidHex() throws {
        let dflt = try #require(CursorHighlightOptions.parse([]).options.color.usingColorSpace(.sRGB))
        let o = try #require(CursorHighlightOptions.parse([("color", .makeString("nope"))]).options.color.usingColorSpace(.sRGB))
        #expect(abs(o.redComponent - dflt.redComponent) < 0.01)
        #expect(abs(o.greenComponent - dflt.greenComponent) < 0.01)
        #expect(abs(o.blueComponent - dflt.blueComponent) < 0.01)
    }

    // Symmetric validation: every ignored input yields exactly one warning,
    // and the resolved option keeps its default.
    @Test func warnsOnInvalidColourAndKeepsDefault() throws {
        let (o, warnings) = CursorHighlightOptions.parse([("color", .makeString("nope"))])
        #expect(warnings.count == 1)
        let c = try #require(o.color.usingColorSpace(.sRGB))
        let dflt = try #require(CursorHighlightOptions.defaults.color.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - dflt.redComponent) < 0.01)
        #expect(abs(c.greenComponent - dflt.greenComponent) < 0.01)
        #expect(abs(c.blueComponent - dflt.blueComponent) < 0.01)
    }

    @Test func warnsOnNonNumericNumberAndKeepsDefault() {
        let (o, warnings) = CursorHighlightOptions.parse([("size", .makeString("big"))])
        #expect(warnings.count == 1)
        #expect(o.size == 240)
    }

    @Test func warnsOnUnknownKeyword() {
        let (o, warnings) = CursorHighlightOptions.parse([("bogus", .fixnum(1))])
        #expect(warnings.count == 1)
        #expect(o.size == 240)
    }

    @Test func collectsOneWarningPerBadInput() {
        let (_, warnings) = CursorHighlightOptions.parse([
            ("color", .makeString("nope")),   // invalid
            ("size", .fixnum(300)),           // valid
            ("glow", .makeString("x")),       // invalid
            ("bogus", .true),                 // unknown
        ])
        #expect(warnings.count == 3)
    }

    @Test func nudgeNeverWarnsForAnyValue() {
        #expect(CursorHighlightOptions.parse([("nudge", .makeString("yes"))]).warnings.isEmpty)
        #expect(CursorHighlightOptions.parse([("nudge", .fixnum(0))]).warnings.isEmpty)
    }
}
