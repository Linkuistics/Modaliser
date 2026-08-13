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

    // MARK: - send-media-key
    //
    // Registration and rejection only. No test here fires a *valid* media key:
    // a successful call posts a real event and toggles whatever the developer
    // is playing. The encoding — the part worth asserting — is covered purely
    // in MediaKeyEmitterTests; the live proof is the local-install task.

    @Test func sendMediaKeyIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? send-media-key)") == .true)
    }

    @Test func sendMediaKeyThrowsForUnknownButton() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate("(send-media-key 'eject)")
            Issue.record("Expected error for unknown media key")
        } catch {
            let message = "\(error)"
            #expect(message.contains("unknown media key"))
            #expect(message.contains("eject"))          // names the offender
            #expect(message.contains("play-pause"))     // lists the valid set
        }
    }

    /// A string is the plausible wrong guess, since every other export in this
    /// library takes one — so it must fail loudly rather than being coerced.
    @Test func sendMediaKeyThrowsForNonSymbol() throws {
        let engine = try SchemeEngine()
        do {
            try engine.evaluate(#"(send-media-key "play-pause")"#)
            Issue.record("Expected type error for a non-symbol media key")
        } catch {
            // RuntimeError.type — any throw is acceptable here.
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
