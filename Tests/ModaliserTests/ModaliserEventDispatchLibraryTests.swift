import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser event-dispatch) library")
struct ModaliserEventDispatchLibraryTests {
    @Test func dispatchProceduresExist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser event-dispatch))")
        #expect(try engine.evaluate("(procedure? modal-key-handler)") == .true)
    }
}
