import Darwin
import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser unix-socket)` — the one native surface the herdr
/// socket transport needs (ADR-0020).
///
/// These exercise the primitive against a throwaway AF_UNIX responder created
/// per test, so nothing here needs a live herdr (or any herdr at all): the
/// primitive is generic by design and knows nothing of herdr, JSON, or the
/// JSON-RPC envelope.
@Suite("Unix Socket Library")
struct UnixSocketLibraryTests {

    @Test func bothProceduresAreExported() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(try engine.evaluate("(procedure? unix-socket-request)") == .true)
        #expect(try engine.evaluate("(procedure? unix-socket-send)") == .true)
    }

    /// The framing contract in both directions: the primitive appends the
    /// newline on send (so the responder's read-to-newline completes) and
    /// strips it on receive (so Scheme sees a bare payload line).
    @Test func roundTripsOneLineThroughAResponder() throws {
        let responder = try LineResponderSocket(behaviour: .echo)
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        let result = try engine.evaluate(
            #"(unix-socket-request "\#(responder.path)" "{\"method\":\"pane.current\"}" 5000)"#
        )
        #expect(result == .makeString(#"echo:{"method":"pane.current"}"#))
    }

    @Test func returnsFalseWhenNothingIsListening() throws {
        let absent = LineResponderSocket.temporarySocketPath()
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(try engine.evaluate(#"(unix-socket-request "\#(absent)" "ping" 5000)"#) == .false)
    }

    /// A peer that accepts but never answers must fail on the deadline, not
    /// wedge the eval thread. The responder holds the connection open for
    /// seconds; the call must come back inside its own 200 ms budget.
    @Test func returnsFalseWhenThePeerNeverResponds() throws {
        let responder = try LineResponderSocket(behaviour: .silent)
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        let started = Date()
        let result = try engine.evaluate(#"(unix-socket-request "\#(responder.path)" "ping" 200)"#)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result == .false)
        #expect(elapsed < 2.0)
        // Without a lower bound this test would also pass on an instant
        // connect failure — the bracket is what pins it to the read deadline.
        #expect(elapsed >= 0.15)
    }

    /// A very large timeout saturates the deadline at DISPATCH_TIME_FOREVER, so
    /// the milliseconds remaining exceed what `poll`'s Int32 budget holds.
    /// Narrowing that would *trap* — crashing the app rather than degrading —
    /// so the round-trip must still simply work.
    @Test func toleratesAnUnreasonablyLargeTimeout() throws {
        let responder = try LineResponderSocket(behaviour: .echo)
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        let result = try engine.evaluate(
            #"(unix-socket-request "\#(responder.path)" "ping" 9223372036854775806)"#
        )
        #expect(result == .makeString("echo:ping"))
    }

    /// `sun_path` is 104 bytes on Darwin. An over-long path is an I/O outcome
    /// (`#f`), not a raise — a leader press must never raise.
    @Test func returnsFalseWhenThePathDoesNotFitSunPath() throws {
        let tooLong = "/tmp/" + String(repeating: "s", count: 200) + ".sock"
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(try engine.evaluate(#"(unix-socket-request "\#(tooLong)" "ping" 5000)"#) == .false)
    }

    /// The other side of that split: malformed arguments are programming
    /// errors and do raise.
    @Test func raisesOnMalformedArguments() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(throws: (any Error).self) {
            try engine.evaluate(#"(unix-socket-request "/tmp/x.sock" "ping" 0)"#)
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate(#"(unix-socket-request 'not-a-path "ping" 100)"#)
        }
    }

    // MARK: - unix-socket-send (the no-reply sibling)

    /// The whole point of the second procedure, and the one property worth
    /// pinning hardest: it does not wait for a reply. The responder here
    /// accepts and then stays silent for seconds, which is exactly what
    /// `unix-socket-request` burns its full deadline on above — `send` must
    /// come back immediately and report success, because success for it means
    /// "the payload is on the wire", not "the peer answered".
    ///
    /// The generous 5 s timeout is deliberate: it would dominate the
    /// measurement if the implementation waited, so a fast return can only
    /// mean it did not.
    @Test func sendReturnsImmediatelyWithoutAwaitingAReply() throws {
        let responder = try LineResponderSocket(behaviour: .silent)
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        let started = Date()
        let result = try engine.evaluate(#"(unix-socket-send "\#(responder.path)" "ping" 5000)"#)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result == .true)
        #expect(elapsed < 1.0)
    }

    /// Not waiting for the reply must not mean not delivering the request:
    /// the bytes are in the peer's buffer before the close, and AF_UNIX
    /// stream delivery hands them over before EOF. Asserted through the
    /// responder's own record of what it read, and including the newline
    /// framing — `send` owns that terminator exactly as `request` does.
    @Test func sendPutsTheExactLineOnTheWire() throws {
        let responder = try LineResponderSocket(behaviour: .canned("ignored"))
        defer { responder.stop() }

        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        let payload = #"{"method":"server.stop"}"#
        #expect(
            try engine.evaluate(
                #"(unix-socket-send "\#(responder.path)" "{\"method\":\"server.stop\"}" 5000)"#
            ) == .true
        )
        // The responder reads to a newline, so having a recorded line at all
        // is itself the proof that the terminator was appended.
        #expect(responder.awaitRequest() == payload)
    }

    /// Failure is still an I/O outcome, never a raise: nothing listening
    /// means the payload never got anywhere, and that is `#f`.
    @Test func sendReturnsFalseWhenNothingIsListening() throws {
        let absent = LineResponderSocket.temporarySocketPath()
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(try engine.evaluate(#"(unix-socket-send "\#(absent)" "ping" 5000)"#) == .false)
    }

    @Test func sendRaisesOnMalformedArguments() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser unix-socket))")
        #expect(throws: (any Error).self) {
            try engine.evaluate(#"(unix-socket-send "/tmp/x.sock" "ping" 0)"#)
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate(#"(unix-socket-send 'not-a-path "ping" 100)"#)
        }
    }
}
