import Testing
import AppKit
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
