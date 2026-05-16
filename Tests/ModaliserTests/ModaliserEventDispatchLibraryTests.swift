import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser event-dispatch) library")
struct ModaliserEventDispatchLibraryTests {
    @Test func dispatchProceduresExist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser event-dispatch))")
        #expect(try engine.evaluate("(procedure? modal-key-handler)") == .true)
        #expect(try engine.evaluate("(procedure? make-leader-handler)") == .true)
    }

    @Test func localContextSuffixDefaultIsFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser event-dispatch))")
        #expect(try engine.evaluate("(local-context-suffix \"com.apple.Safari\")") == .false)
    }
}
