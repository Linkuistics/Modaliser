import Testing
import CoreGraphics
@testable import Modaliser

@Suite("KeyCodeMapping")
struct KeyCodeMappingTests {

    @Test func letterKeysMapToCharacters() {
        #expect(KeyCodeMapping.character(for: 0) == "a")
        #expect(KeyCodeMapping.character(for: 1) == "s")
        #expect(KeyCodeMapping.character(for: 2) == "d")
        #expect(KeyCodeMapping.character(for: 3) == "f")
        #expect(KeyCodeMapping.character(for: 11) == "b")
        #expect(KeyCodeMapping.character(for: 45) == "n")
        #expect(KeyCodeMapping.character(for: 46) == "m")
    }

    @Test func digitKeysMapToStrings() {
        #expect(KeyCodeMapping.character(for: 29) == "0")
        #expect(KeyCodeMapping.character(for: 18) == "1")
        #expect(KeyCodeMapping.character(for: 19) == "2")
        #expect(KeyCodeMapping.character(for: 23) == "5")
        #expect(KeyCodeMapping.character(for: 25) == "9")
    }

    @Test func punctuationKeysMap() {
        #expect(KeyCodeMapping.character(for: 43) == ",")
        #expect(KeyCodeMapping.character(for: 47) == ".")
        #expect(KeyCodeMapping.character(for: 44) == "/")
        #expect(KeyCodeMapping.character(for: 41) == ";")
        #expect(KeyCodeMapping.character(for: 39) == "'")
        #expect(KeyCodeMapping.character(for: 27) == "-")
        #expect(KeyCodeMapping.character(for: 24) == "=")
        #expect(KeyCodeMapping.character(for: 33) == "[")
        #expect(KeyCodeMapping.character(for: 30) == "]")
        #expect(KeyCodeMapping.character(for: 42) == "\\")
        #expect(KeyCodeMapping.character(for: 50) == "`")
    }

    @Test func spaceKeyMaps() {
        #expect(KeyCodeMapping.character(for: KeyCode.space) == " ")
    }

    @Test func unknownKeyCodeReturnsNil() {
        // F-keys and modifier keys should not map to characters
        #expect(KeyCodeMapping.character(for: KeyCode.f17) == nil)
        #expect(KeyCodeMapping.character(for: KeyCode.f18) == nil)
        #expect(KeyCodeMapping.character(for: KeyCode.escape) == nil)
        #expect(KeyCodeMapping.character(for: KeyCode.delete) == nil)
        #expect(KeyCodeMapping.character(for: KeyCode.returnKey) == nil)
    }
}
