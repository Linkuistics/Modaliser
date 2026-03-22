import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("Fuzzy Match Library (modaliser fuzzy)")
struct FuzzyMatchLibraryTests {

    // MARK: - fuzzy-match (single string)

    @Test func exactMatchReturnsHighScore() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(fuzzy-match "safari" "Safari")"#)
        // Should return (score (indices...))
        #expect(result != .false)
        let score = try engine.evaluate(#"(car (fuzzy-match "safari" "Safari"))"#)
        #expect(try score.asInt64() > 0)
    }

    @Test func noMatchReturnsFalse() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate(#"(fuzzy-match "xyz" "Safari")"#) == .false)
    }

    @Test func emptyQueryMatchesEverything() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(fuzzy-match "" "Safari")"#)
        #expect(result != .false)
        #expect(try engine.evaluate(#"(car (fuzzy-match "" "anything"))"#).asInt64() == 1)
    }

    @Test func matchedIndicesAreReturned() throws {
        let engine = try SchemeEngine()
        // "sf" in "Safari" → should match at positions 0 and 2
        let result = try engine.evaluate(#"(fuzzy-match "sf" "Safari")"#)
        #expect(result != .false)
        let indices = try engine.evaluate(#"(cadr (fuzzy-match "sf" "Safari"))"#)
        #expect(indices != .null)
    }

    @Test func caseInsensitiveMatching() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(fuzzy-match "SAF" "safari")"#)
        #expect(result != .false)
    }

    @Test func queryLongerThanTargetReturnsFalse() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate(#"(fuzzy-match "longerquery" "short")"#) == .false)
    }

    @Test func wordBoundaryMatchesScoredHigher() throws {
        let engine = try SchemeEngine()
        // "fb" in "FooBar" (word boundary) should score higher than "fb" in "fxxb" (gap)
        let wordBoundary = try engine.evaluate(#"(car (fuzzy-match "fb" "FooBar"))"#).asInt64()
        let gapMatch = try engine.evaluate(#"(car (fuzzy-match "fb" "fxxb"))"#).asInt64()
        #expect(wordBoundary > gapMatch)
    }

    @Test func consecutiveMatchesScoredHigher() throws {
        let engine = try SchemeEngine()
        // "abc" consecutive in "abcdef" should score higher than scattered in "axbxcx"
        let consecutive = try engine.evaluate(#"(car (fuzzy-match "abc" "abcdef"))"#).asInt64()
        let scattered = try engine.evaluate(#"(car (fuzzy-match "abc" "axbxcx"))"#).asInt64()
        #expect(consecutive > scattered)
    }

    // MARK: - fuzzy-filter (batch)

    @Test func fuzzyFilterReturnsMatchingItems() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("""
            (fuzzy-filter "saf" '("Safari" "Chrome" "Firefox" "Safeguard"))
            """)
        // Should return entries for Safari and Safeguard, not Chrome/Firefox
        let count = try engine.evaluate("""
            (length (fuzzy-filter "saf" '("Safari" "Chrome" "Firefox" "Safeguard")))
            """)
        #expect(try count.asInt64() == 2)
    }

    @Test func fuzzyFilterReturnsSortedByScore() throws {
        let engine = try SchemeEngine()
        // "chr" should score "Chrome" higher than "Unchromable" (word boundary vs mid-word)
        let firstIndex = try engine.evaluate("""
            (car (car (fuzzy-filter "chr" '("Unchromable" "Chrome"))))
            """)
        // Chrome is at index 1, should be first result (word boundary bonus)
        #expect(try firstIndex.asInt64() == 1)
    }

    @Test func fuzzyFilterEmptyQueryReturnsAll() throws {
        let engine = try SchemeEngine()
        let count = try engine.evaluate("""
            (length (fuzzy-filter "" '("a" "b" "c")))
            """)
        #expect(try count.asInt64() == 3)
    }

    @Test func fuzzyFilterEmptyListReturnsEmpty() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("""
            (fuzzy-filter "test" '())
            """)
        #expect(result == .null)
    }

    @Test func fuzzyFilterResultContainsIndexScoreAndIndices() throws {
        let engine = try SchemeEngine()
        // Each result entry is (index score (matched-indices...))
        let entry = try engine.evaluate("""
            (car (fuzzy-filter "s" '("Safari")))
            """)
        let index = try engine.evaluate("""
            (car (car (fuzzy-filter "s" '("Safari"))))
            """)
        #expect(try index.asInt64() == 0)

        let score = try engine.evaluate("""
            (cadr (car (fuzzy-filter "s" '("Safari"))))
            """)
        #expect(try score.asInt64() > 0)
    }

    // MARK: - Procedure existence

    @Test func fuzzyMatchProceduresExist() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? fuzzy-match)") == .true)
        #expect(try engine.evaluate("(procedure? fuzzy-filter)") == .true)
    }
}
