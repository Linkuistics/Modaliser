import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser instrument)` — the leader-press stopwatch and
/// string-scan tripwire added by `measure-hot-scan-k2`.
///
/// The point of this suite is that the instrument is **inert by default**
/// and only the host turns it on (root.scm's marker file), which means the
/// rest of the suite exercises it in its off state and proves nothing about
/// whether it counts. So these tests drive it in both states through
/// `instrument-site`, the read-back accessor that exists so the counters can
/// be checked without reading the unified log by eye — i.e. without trusting
/// the instrument under test to report on itself.
@Suite("Instrument Library")
struct InstrumentLibraryTests {

    private func engineWithInstrument() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser instrument))")
        return engine
    }

    // ─── Inert by default ────────────────────────────────────────────

    @Test func disabledByDefault() throws {
        let engine = try engineWithInstrument()
        #expect(try engine.evaluate("(instrument-enabled?)") == .false)
    }

    /// The load-bearing property: a bare `SchemeEngine()` never runs
    /// root.scm, so every span and counter in the library tree must be a
    /// parameter read and a return. A tally that still recorded while
    /// disabled would make every test in this suite an accumulating
    /// measurement of nothing.
    @Test func countsNothingWhileDisabled() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("(instrument-tally! 'off-site 100)")
        try engine.evaluate(#"(instrument-sample! 'off-site "hello" 5)"#)
        #expect(try engine.evaluate("(instrument-site 'off-site)") == .false)
    }

    // ─── Counting, when enabled ──────────────────────────────────────

    @Test func tallyAccumulatesCallsTotalAndMax() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-reset! 'test)
            (instrument-tally! 'site 10)
            (instrument-tally! 'site 400)
            (instrument-tally! 'site 30))
          """)
        // calls, total-chars, max-chars — max is the field that names a
        // payload's size, so it must be a maximum and not the last value.
        #expect(try engine.evaluate("(vector-ref (instrument-site 'site) 0)") == .fixnum(3))
        #expect(try engine.evaluate("(vector-ref (instrument-site 'site) 1)") == .fixnum(440))
        #expect(try engine.evaluate("(vector-ref (instrument-site 'site) 2)") == .fixnum(400))
    }

    @Test func sitesAreIndependent() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-reset! 'test)
            (instrument-tally! 'a 1)
            (instrument-tally! 'b 2)
            (instrument-tally! 'b 3))
          """)
        #expect(try engine.evaluate("(vector-ref (instrument-site 'a) 0)") == .fixnum(1))
        #expect(try engine.evaluate("(vector-ref (instrument-site 'b) 0)") == .fixnum(2))
    }

    /// The epoch boundary is what makes a report read "since this press"
    /// rather than "since launch" — a counter that survived the reset would
    /// silently turn every reading into a lifetime total.
    @Test func resetClearsTheTable() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-tally! 'site 10)
            (instrument-reset! 'next-press))
          """)
        #expect(try engine.evaluate("(instrument-site 'site)") == .false)
    }

    /// `instrument-site` hands back a copy: the live cell is shared with the
    /// hot path, so a reader that could write it could corrupt a measurement.
    @Test func siteReadbackIsACopy() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-reset! 'test)
            (instrument-tally! 'site 7))
          """)
        try engine.evaluate("(vector-set! (instrument-site 'site) 0 999)")
        #expect(try engine.evaluate("(vector-ref (instrument-site 'site) 0)") == .fixnum(1))
    }

    // ─── The span ────────────────────────────────────────────────────

    /// A stopwatch that changed a result would be worse than no stopwatch:
    /// every span in the tree wraps a value the caller goes on to use.
    @Test func spanReturnsTheThunkValueWhenDisabled() throws {
        let engine = try engineWithInstrument()
        #expect(try engine.evaluate("(instrument-span 'x (lambda () 42))") == .fixnum(42))
    }

    @Test func spanReturnsTheThunkValueWhenEnabled() throws {
        let engine = try engineWithInstrument()
        let result = try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-span 'x (lambda () 42)))
          """)
        #expect(result == .fixnum(42))
    }

    // ─── The tripwire ────────────────────────────────────────────────

    /// `instrument-sample!` tallies whatever it is handed; the threshold
    /// gates only the prefix LINE it logs, never the counting. Getting this
    /// backwards would hide exactly the "many scans of a smallish string"
    /// shape that a 27 s press over a 4.3 KB payload implies.
    @Test func sampleTalliesBelowTheThreshold() throws {
        let engine = try engineWithInstrument()
        try engine.evaluate("""
          (parameterize ((instrument-enabled? #t))
            (instrument-reset! 'test)
            (instrument-sample! 'small "abc" 3)
            (instrument-sample! 'small "abcd" 4))
          """)
        #expect(try engine.evaluate("(vector-ref (instrument-site 'small) 0)") == .fixnum(2))
        #expect(try engine.evaluate("(vector-ref (instrument-site 'small) 2)") == .fixnum(4))
    }

    /// A string longer than the threshold takes the prefix-logging path,
    /// which slices the string — the one place the instrument touches the
    /// payload rather than just counting it, and so the one place it could
    /// raise on a short-but-declared-long argument.
    @Test func sampleAboveThresholdDoesNotRaise() throws {
        let engine = try engineWithInstrument()
        let result = try engine.evaluate("""
          (parameterize ((instrument-enabled? #t) (instrument-threshold 4))
            (instrument-reset! 'test)
            (instrument-sample! 'big "abcdefghij" 10)
            (vector-ref (instrument-site 'big) 2))
          """)
        #expect(result == .fixnum(10))
    }

    /// The threshold is a parameter so a measurement can be widened or
    /// narrowed without a rebuild of the whole tree.
    @Test func thresholdIsParameterizable() throws {
        let engine = try engineWithInstrument()
        #expect(try engine.evaluate("(instrument-threshold)") == .fixnum(4096))
    }
}
