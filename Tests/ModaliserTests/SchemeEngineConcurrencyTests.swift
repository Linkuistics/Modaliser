import Testing
import LispKit
@testable import Modaliser

@Suite("SchemeEngine evaluation serialization")
struct SchemeEngineConcurrencyTests {

    /// Regression: an `after-delay` callback fires on the main queue while
    /// the engine that armed it is still mid-evaluation on a test thread.
    ///
    /// In the app every evaluation runs on the main thread, so the run loop
    /// serializes timer callbacks against everything else. Swift Testing
    /// runs @Test bodies on cooperative-pool threads while the process main
    /// thread drains DispatchQueue.main — so before the per-engine eval
    /// fence, the callback re-entered the busy VirtualMachine and tripped
    /// LispKit's assertTopLevel precondition, killing the whole test
    /// process (signal 5). The single 0.6s evaluation below is guaranteed
    /// to span the 0.1s timer deadline.
    @Test func afterDelayCallbackDuringEvaluationDoesNotCrash() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (scheme time))")
        try engine.evaluate("(after-delay 0.1 (lambda () 'fired))")
        _ = try engine.evaluate("""
            (let ((start (current-second)))
              (let loop ((i 0))
                (if (< (- (current-second) start) 0.6)
                    (loop (+ i 1))
                    i)))
            """)
    }
}
