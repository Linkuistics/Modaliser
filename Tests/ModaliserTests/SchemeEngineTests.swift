import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("SchemeEngine")
struct SchemeEngineTests {
    @Test func evaluateSimpleExpression() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(+ 1 2 3)")
        #expect(result == .fixnum(6))
    }

    @Test func evaluateStringExpression() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("\"hello\"")
        if case .string = result {
            // expected
        } else {
            #expect(Bool(false), "Expected string, got \(result)")
        }
    }

    @Test func evaluateDefineAndLookup() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("(define x 42)")
        let result = try engine.evaluate("x")
        #expect(result == .fixnum(42))
    }

    @Test func evaluateLambdaDefinition() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("(define add1 (lambda (n) (+ n 1)))")
        let result = try engine.evaluate("(add1 10)")
        #expect(result == .fixnum(11))
    }

    @Test func registryIsAccessible() throws {
        let engine = try SchemeEngine()
        #expect(engine.registry.tree(for: .global) == nil)
    }

    @Test func evaluateFileLoadsSchemeCode() throws {
        let engine = try SchemeEngine()
        let tempDir = NSTemporaryDirectory()
        let filePath = tempDir + "test-eval-\(ProcessInfo.processInfo.globallyUniqueString).scm"
        try "(define test-val 99)".write(toFile: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: filePath) }

        try engine.evaluateFile(filePath)
        let result = try engine.evaluate("test-val")
        #expect(result == .fixnum(99))
    }
}
