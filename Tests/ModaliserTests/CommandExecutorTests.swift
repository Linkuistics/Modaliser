import Testing
import LispKit
@testable import Modaliser

@Suite("CommandExecutor")
struct CommandExecutorTests {

    // MARK: - Helpers

    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    // MARK: - Execute Scheme lambdas

    @Test func executeZeroArgLambdaReturnsResult() throws {
        let engine = try makeEngine()
        let lambda = try engine.evaluate("(lambda () 42)")
        let executor = CommandExecutor(engine: engine)
        let result = try executor.execute(action: lambda)
        #expect(result == .fixnum(42))
    }

    @Test func executeLambdaThatReturnsList() throws {
        let engine = try makeEngine()
        let lambda = try engine.evaluate("""
            (lambda () (list 'launch-app "Safari"))
            """)
        let executor = CommandExecutor(engine: engine)
        let result = try executor.execute(action: lambda)
        // Result should be a pair (list), not void
        if case .pair = result {
            // expected — it's a list
        } else {
            #expect(Bool(false), "Expected a list, got \(result)")
        }
    }

    @Test func executeLambdaWithSideEffect() throws {
        let engine = try makeEngine()
        // Define a mutable variable, lambda mutates it
        _ = try engine.evaluate("(define side-effect-counter 0)")
        let lambda = try engine.evaluate("""
            (lambda () (set! side-effect-counter (+ side-effect-counter 1)))
            """)
        let executor = CommandExecutor(engine: engine)
        _ = try executor.execute(action: lambda)
        let counter = try engine.evaluate("side-effect-counter")
        #expect(counter == .fixnum(1))
    }

    @Test func executeMultipleLambdasAccumulateSideEffects() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define call-log '())")
        let lambdaA = try engine.evaluate("""
            (lambda () (set! call-log (cons 'a call-log)))
            """)
        let lambdaB = try engine.evaluate("""
            (lambda () (set! call-log (cons 'b call-log)))
            """)
        let executor = CommandExecutor(engine: engine)
        _ = try executor.execute(action: lambdaA)
        _ = try executor.execute(action: lambdaB)
        // Should be (b a) — most recent first
        let length = try engine.evaluate("(length call-log)")
        #expect(length == .fixnum(2))
    }

    @Test func executeNonProcedureThrows() throws {
        let engine = try makeEngine()
        let executor = CommandExecutor(engine: engine)
        #expect(throws: (any Error).self) {
            _ = try executor.execute(action: .fixnum(42))
        }
    }

    @Test func executeLambdaThatThrowsReportsError() throws {
        let engine = try makeEngine()
        let lambda = try engine.evaluate("""
            (lambda () (error "deliberate error" "test"))
            """)
        let executor = CommandExecutor(engine: engine)
        #expect(throws: (any Error).self) {
            _ = try executor.execute(action: lambda)
        }
    }

    // MARK: - Execute with argument (for selector callbacks)

    @Test func executeWithArgumentPassesValueToLambda() throws {
        let engine = try makeEngine()
        let lambda = try engine.evaluate("(lambda (x) (+ x 10))")
        let executor = CommandExecutor(engine: engine)
        let result = try executor.execute(action: lambda, argument: .fixnum(5))
        #expect(result == .fixnum(15))
    }

    @Test func executeWithAlistArgumentExtractsField() throws {
        let engine = try makeEngine()
        let lambda = try engine.evaluate("""
            (lambda (choice) (cdr (assoc 'text choice)))
            """)
        let alist = try engine.evaluate("""
            (list (cons 'text "Safari") (cons 'icon "com.apple.Safari"))
            """)
        let executor = CommandExecutor(engine: engine)
        let result = try executor.execute(action: lambda, argument: alist)
        #expect(result == .makeString("Safari"))
    }

    @Test func executeWithArgumentNonProcedureThrows() throws {
        let engine = try makeEngine()
        let executor = CommandExecutor(engine: engine)
        #expect(throws: (any Error).self) {
            _ = try executor.execute(action: .fixnum(42), argument: .null)
        }
    }
}
