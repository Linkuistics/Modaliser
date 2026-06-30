import Testing
@testable import Modaliser

@Suite("Hints Library — named groups")
struct HintsLibraryTests {

    @Test func hintsProceduresExist() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? hints-show)") == .true)
        #expect(try engine.evaluate("(procedure? hints-hide)") == .true)
        #expect(try engine.evaluate("(procedure? hints-show-in)") == .true)
        #expect(try engine.evaluate("(procedure? hints-hide-in)") == .true)
    }

    @Test func namedGroupShowHideDoesNotThrow() throws {
        // Empty hint-list paints no panels (safe in a headless test), so this
        // exercises the group-keyed show/hide plumbing without creating UI.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser hints))")
        #expect(try engine.evaluate("(begin (hints-show-in 'displays '()) #t)") == .true)
        #expect(try engine.evaluate("(begin (hints-hide-in 'displays) #t)") == .true)
        #expect(try engine.evaluate("(begin (hints-show '()) #t)") == .true)
        #expect(try engine.evaluate("(begin (hints-hide) #t)") == .true)
    }
}
