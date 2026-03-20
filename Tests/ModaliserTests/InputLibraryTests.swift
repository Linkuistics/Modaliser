import Testing
import LispKit
@testable import Modaliser

@Suite("Input Library")
struct InputLibraryTests {

    // MARK: - Library registration

    @Test func sendKeystrokeFunctionExists() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("send-keystroke")
    }

    @Test func sendKeystrokeIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? send-keystroke)") == .true)
    }

    // MARK: - Error handling

    @Test func sendKeystrokeThrowsForUnknownKey() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-keystroke '() "nonexistent_key")"#)
            Issue.record("Expected error for unknown key")
        } catch {
            let message = "\(error)"
            #expect(message.contains("unknown key"))
        }
    }
}
