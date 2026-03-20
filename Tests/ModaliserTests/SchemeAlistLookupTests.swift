import Testing
import LispKit
@testable import Modaliser

@Suite("SchemeAlistLookup")
struct SchemeAlistLookupTests {

    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    // MARK: - lookupString

    @Test func lookupStringFindsExistingKey() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate(#"(list (cons 'name "Safari") (cons 'path "/Applications/Safari.app"))"#)
        #expect(SchemeAlistLookup.lookupString(alist, key: "name") == "Safari")
        #expect(SchemeAlistLookup.lookupString(alist, key: "path") == "/Applications/Safari.app")
    }

    @Test func lookupStringReturnsNilForMissingKey() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate(#"(list (cons 'name "Safari"))"#)
        #expect(SchemeAlistLookup.lookupString(alist, key: "missing") == nil)
    }

    @Test func lookupStringReturnsNilForNonStringValue() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate("(list (cons 'count 42))")
        #expect(SchemeAlistLookup.lookupString(alist, key: "count") == nil)
    }

    @Test func lookupStringReturnsNilForEmptyAlist() {
        #expect(SchemeAlistLookup.lookupString(.null, key: "any") == nil)
    }

    // MARK: - lookupFixnum

    @Test func lookupFixnumFindsExistingKey() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate("(list (cons 'pid 1234) (cons 'windowId 5678))")
        #expect(SchemeAlistLookup.lookupFixnum(alist, key: "pid") == 1234)
        #expect(SchemeAlistLookup.lookupFixnum(alist, key: "windowId") == 5678)
    }

    @Test func lookupFixnumReturnsNilForMissingKey() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate("(list (cons 'pid 1234))")
        #expect(SchemeAlistLookup.lookupFixnum(alist, key: "missing") == nil)
    }

    @Test func lookupFixnumReturnsNilForStringValue() throws {
        let engine = try makeEngine()
        let alist = try engine.evaluate(#"(list (cons 'name "Safari"))"#)
        #expect(SchemeAlistLookup.lookupFixnum(alist, key: "name") == nil)
    }

    // MARK: - makeAlist

    @Test func makeAlistCreatesValidSchemeAlist() throws {
        let engine = try makeEngine()
        let symbols = engine.context.symbols
        let alist = SchemeAlistLookup.makeAlist([
            ("text", .makeString("hello")),
            ("count", .fixnum(42)),
        ], symbols: symbols)

        #expect(SchemeAlistLookup.lookupString(alist, key: "text") == "hello")
        #expect(SchemeAlistLookup.lookupFixnum(alist, key: "count") == 42)
    }

    @Test func makeAlistPreservesInsertionOrder() throws {
        let engine = try makeEngine()
        let symbols = engine.context.symbols
        let alist = SchemeAlistLookup.makeAlist([
            ("first", .makeString("a")),
            ("second", .makeString("b")),
        ], symbols: symbols)

        // First entry should be "first"
        if case .pair(.pair(.symbol(let s), _), _) = alist {
            #expect(s.identifier == "first")
        } else {
            Issue.record("Expected alist pair structure")
        }
    }
}
