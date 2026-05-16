import Foundation
import Testing
@testable import Modaliser

@Suite("Scheme base resolution")
struct SchemeBaseProbeTests {
    @Test func schemeBaseResolvesInDefineLibrary() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
            (define-library (probe one)
              (export greet)
              (import (scheme base))
              (begin
                (define (greet) "hello-from-probe")))
        """)
        try engine.evaluate("(import (probe one))")
        #expect(try engine.evaluate("(greet)").asString() == "hello-from-probe")
    }
}
