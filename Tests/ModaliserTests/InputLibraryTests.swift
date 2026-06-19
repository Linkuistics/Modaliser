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

    // MARK: - send-key-down / send-key-up registration

    @Test func sendKeyDownIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? send-key-down)") == .true)
    }

    @Test func sendKeyUpIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? send-key-up)") == .true)
    }

    @Test func sendKeyDownThrowsForUnknownKey() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-key-down '() "nonexistent_key")"#)
            Issue.record("Expected error for unknown key")
        } catch {
            #expect("\(error)".contains("unknown key"))
        }
    }

    // MARK: - Single-argument (no-modifier) arity

    /// The one-arg form treats its argument as the key with no modifiers —
    /// reaching key resolution (and throwing for an unknown key) proves the
    /// arg was read as the key, not as a modifier list.
    @Test func sendKeyDownSingleArgIsKeyOnly() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-key-down "nonexistent_key")"#)
            Issue.record("Expected error for unknown key")
        } catch {
            #expect("\(error)".contains("unknown key"))
        }
    }

    @Test func sendKeystrokeSingleArgIsKeyOnly() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-keystroke "nonexistent_key")"#)
            Issue.record("Expected error for unknown key")
        } catch {
            #expect("\(error)".contains("unknown key"))
        }
    }

    @Test func sendKeystrokeTooManyArgsThrows() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-keystroke '() "a" "extra")"#)
            Issue.record("Expected argument-count error")
        } catch {
            // RuntimeError.argumentCount — any throw is acceptable here.
        }
    }
}
