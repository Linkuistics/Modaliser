import Testing
import LispKit
@testable import Modaliser

@Suite("SelectorSourceInvoker")
struct SelectorSourceInvokerTests {

    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    // MARK: - Basic invocation

    @Test func invokeSourceReturnsChoices() throws {
        let engine = try makeEngine()
        let source = try engine.evaluate("""
            (lambda ()
              (list
                (list (cons 'text "Safari") (cons 'subText "/Applications/Safari.app"))
                (list (cons 'text "Mail") (cons 'subText "/Applications/Mail.app"))))
            """)
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)
        #expect(choices.count == 2)
        #expect(choices[0].text == "Safari")
        #expect(choices[0].subText == "/Applications/Safari.app")
        #expect(choices[1].text == "Mail")
        #expect(choices[1].subText == "/Applications/Mail.app")
    }

    @Test func invokeSourceWithIconFields() throws {
        let engine = try makeEngine()
        let source = try engine.evaluate("""
            (lambda ()
              (list
                (list (cons 'text "Safari")
                      (cons 'icon "com.apple.Safari")
                      (cons 'iconType "bundleId"))))
            """)
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)
        #expect(choices[0].icon == "com.apple.Safari")
        #expect(choices[0].iconType == "bundleId")
    }

    @Test func invokeSourceWithMinimalFields() throws {
        let engine = try makeEngine()
        let source = try engine.evaluate("""
            (lambda ()
              (list (list (cons 'text "Item"))))
            """)
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)
        #expect(choices.count == 1)
        #expect(choices[0].text == "Item")
        #expect(choices[0].subText == nil)
        #expect(choices[0].icon == nil)
        #expect(choices[0].iconType == nil)
    }

    @Test func invokeSourceEmptyListReturnsEmpty() throws {
        let engine = try makeEngine()
        let source = try engine.evaluate("(lambda () '())")
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)
        #expect(choices.isEmpty)
    }

    // MARK: - Round-tripping

    @Test func choiceRetainsOriginalSchemeValue() throws {
        let engine = try makeEngine()
        let source = try engine.evaluate("""
            (lambda ()
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))))
            """)
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)

        // The schemeValue should be the original alist, which we can query
        let bundleId = try engine.evaluate("""
            (cdr (assoc 'bundleId '\(choices[0].schemeValue)))
            """)
        #expect(bundleId == .makeString("com.apple.Safari"))
    }

    // MARK: - Error handling

    @Test func invokeNonProcedureThrows() throws {
        let engine = try makeEngine()
        let invoker = SelectorSourceInvoker(engine: engine)
        #expect(throws: (any Error).self) {
            _ = try invoker.invoke(source: .fixnum(42))
        }
    }
}
