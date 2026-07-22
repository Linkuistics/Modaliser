import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser log)` — the one Scheme-facing diagnostic
/// primitive (ADR-0017 Layer 2). os.Logger's actual readback via
/// `log show` isn't exercisable from a unit test (requires the installed
/// .app + a real missing tool, per the leaf's own "Done when"); these
/// tests only confirm the binding exists, evaluates without raising, and
/// accepts the shapes callers pass.
@Suite("Log Library")
struct LogLibraryTests {
    @Test func logLineIsExportedProcedure() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser log))")
        #expect(try engine.evaluate("(procedure? log-line)") == .true)
    }

    @Test func logLineAcceptsAStringAndReturnsVoid() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser log))")
        let result = try engine.evaluate(#"(log-line "backend-health-surfacing-k37 smoke test")"#)
        #expect(result == .void)
    }

    @Test func logLineAcceptsAnEmptyString() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser log))")
        let result = try engine.evaluate(#"(log-line "")"#)
        #expect(result == .void)
    }
}
