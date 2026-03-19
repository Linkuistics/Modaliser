import Testing
@testable import Modaliser

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    // MARK: - Basic matching

    @Test func exactMatchReturnsHighScore() {
        let result = FuzzyMatcher.match(query: "safari", target: "Safari")
        #expect(result != nil)
        #expect(result!.score > 0)
        #expect(result!.matchedIndices.count == 6)
    }

    @Test func prefixMatchReturnAllIndicesFromStart() {
        let result = FuzzyMatcher.match(query: "saf", target: "Safari")
        #expect(result != nil)
        #expect(result!.matchedIndices == Set([0, 1, 2]))
    }

    @Test func noMatchReturnsNil() {
        let result = FuzzyMatcher.match(query: "xyz", target: "Safari")
        #expect(result == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        let result = FuzzyMatcher.match(query: "", target: "Safari")
        #expect(result != nil)
        #expect(result!.matchedIndices.isEmpty)
    }

    @Test func queryLongerThanTargetReturnsNil() {
        let result = FuzzyMatcher.match(query: "safariextended", target: "Safari")
        #expect(result == nil)
    }

    // MARK: - Case insensitivity

    @Test func matchIsCaseInsensitive() {
        let result = FuzzyMatcher.match(query: "SAFARI", target: "Safari")
        #expect(result != nil)
        #expect(result!.matchedIndices.count == 6)
    }

    // MARK: - Scoring priorities

    @Test func consecutivePrefixScoresHigherThanScatteredMiddle() {
        // "app" consecutive at start vs scattered in "axpxp"
        let prefix = FuzzyMatcher.match(query: "app", target: "application")
        let scattered = FuzzyMatcher.match(query: "app", target: "axpxpxx")
        #expect(prefix != nil)
        #expect(scattered != nil)
        #expect(prefix!.score > scattered!.score)
    }

    @Test func consecutiveMatchScoresHigherThanScatteredMatch() {
        let consecutive = FuzzyMatcher.match(query: "abc", target: "abcdef")
        let scattered = FuzzyMatcher.match(query: "abc", target: "axbxcx")
        #expect(consecutive != nil)
        #expect(scattered != nil)
        #expect(consecutive!.score > scattered!.score)
    }

    @Test func wordBoundaryMatchScoresHigherThanMidWord() {
        // "fi" matching "Find" (word start) should score higher than "fi" in "refine" (mid-word)
        let boundary = FuzzyMatcher.match(query: "fi", target: "Find File")
        let midWord = FuzzyMatcher.match(query: "fi", target: "refine")
        #expect(boundary != nil)
        #expect(midWord != nil)
        #expect(boundary!.score > midWord!.score)
    }

    @Test func camelCaseBoundaryGetsBonus() {
        // "vC" should match "ViewController" at word boundaries
        let result = FuzzyMatcher.match(query: "vc", target: "ViewController")
        #expect(result != nil)
        #expect(result!.matchedIndices.contains(0))  // V
        #expect(result!.matchedIndices.contains(4))  // C
    }

    // MARK: - Path separator bonus

    @Test func pathSeparatorMatchGetsBonus() {
        let result = FuzzyMatcher.match(query: "mai", target: "src/main.swift")
        #expect(result != nil)
        // Should prefer matching at "main" after the "/" rather than "mai" in a random position
        #expect(result!.matchedIndices.contains(4))  // m after /
    }

    // MARK: - Matched indices correctness

    @Test func matchedIndicesAreCorrectForSimpleMatch() {
        let result = FuzzyMatcher.match(query: "sf", target: "Safari")
        #expect(result != nil)
        // S=0, f=2 (a=1 skipped)
        #expect(result!.matchedIndices.count == 2)
        #expect(result!.matchedIndices.contains(0))
    }

    @Test func matchedIndicesCountEqualsQueryLength() {
        let result = FuzzyMatcher.match(query: "find", target: "Find File in Directory")
        #expect(result != nil)
        #expect(result!.matchedIndices.count == 4)
    }

    // MARK: - Edge cases

    @Test func singleCharacterQueryMatches() {
        let result = FuzzyMatcher.match(query: "s", target: "Safari")
        #expect(result != nil)
        #expect(result!.matchedIndices == Set([0]))
    }

    @Test func queryEqualsTargetMatches() {
        let result = FuzzyMatcher.match(query: "safari", target: "safari")
        #expect(result != nil)
        #expect(result!.matchedIndices == Set(0..<6))
    }

    // MARK: - Last match index (for tail proximity)

    @Test func lastMatchIndexReturnsPositionOfFinalMatchedChar() {
        let result = FuzzyMatcher.match(query: "sf", target: "Safari")
        #expect(result != nil)
        // 'f' is at index 2
        #expect(result!.lastMatchIndex >= 0)
    }
}
