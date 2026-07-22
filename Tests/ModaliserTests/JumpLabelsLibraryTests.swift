import Foundation
import Testing
@testable import Modaliser

// Unit tests for the (modaliser jump-labels) library — the portable,
// pure-function jump-label assignment utility behind the herdr jump space
// (jump-labels-k4). Ordered targets + three constraint alphabets in,
// prefix-free one- or two-key labels out (docs/specs/herdr-jump-navigation.md).
@Suite("(modaliser jump-labels) library")
struct JumpLabelsLibraryTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser jump-labels) (modaliser util))")
        // A generic prefix-free validator, defined once per engine so tests
        // can check the PROPERTY (no label a proper prefix of another)
        // rather than only the specific expected label sequence.
        try engine.evaluate("""
          (define (prefix? a b)
            (and (< (string-length a) (string-length b))
                 (string=? a (substring b 0 (string-length a)))))
          (define (conflicts? h rest)
            (if (find (lambda (o) (or (prefix? h o) (prefix? o h))) rest) #t #f))
          (define (all-prefix-free? labels)
            (let loop ((ls labels))
              (cond ((null? ls) #t)
                    ((conflicts? (car ls) (cdr ls)) #f)
                    (else (loop (cdr ls))))))
        """)
        return engine
    }

    // Fewer targets than the single alphabet: every target gets a one-key
    // label straight from single-alphabet order — no leader is ever touched.
    @Test func fewerTargetsThanSinglesUsesOnlySingles() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign '(t1 t2 t3)
                           '("a" "s" "d") '("a" "s" "d") '("q" "w" "e")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result) '("a" "s" "d"))
        """) == .true)
        #expect(try engine.evaluate("(equal? (map cdr result) '(t1 t2 t3))") == .true)
    }

    // More targets than singles can cover: the minimum number of leaders
    // (here just one, "a") escalate to two-key duty, in leader-alphabet
    // order; the rest of the alphabet ("s" "d") keeps single-key labels.
    @Test func escalationPromotesMinimumOverlappingLeaders() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign '(t1 t2 t3 t4 t5)
                           '("a" "s" "d") '("a" "s" "d")
                           '("q" "w" "e" "r" "t" "y" "u" "i" "o" "p")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result) '("s" "d" "aq" "aw" "ae"))
        """) == .true)
    }

    // A leader-alphabet disjoint from single-alphabet costs nothing: escalating
    // into it never removes a single-key label from the pool.
    @Test func disjointLeadersDoNotCostSingles() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign '(t1 t2 t3 t4 t5)
                           '("a" "s" "d") '("q" "w" "e") '("1" "2")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result) '("a" "s" "d" "q1" "q2"))
        """) == .true)
    }

    // With a one-member second-alphabet, promoting a leader that is ALSO a
    // single-alphabet member nets zero extra capacity (lose one single, gain
    // one two-key label) — never beneficial, so it must be skipped in favour
    // of a later, non-overlapping leader. "a" stays a single; "q" escalates.
    @Test func nonBeneficialLeaderIsSkipped() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign '(t1 t2 t3 t4)
                           '("a" "s" "d") '("a" "q") '("1")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result) '("a" "s" "d" "q1"))
        """) == .true)
    }

    // More targets than the entire label space (singles + every reachable
    // two-key combination): the unlabelled tail gets #f, in position — the
    // output stays the same length and order as the input targets.
    @Test func moreTargetsThanLabelSpaceLeavesUnlabelledTail() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign '(t1 t2 t3) '("a") '() '()))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result) (list "a" #f #f))
        """) == .true)
        #expect(try engine.evaluate("(equal? (map cdr result) '(t1 t2 t3))") == .true)
    }

    // Deterministic: identical inputs (including target order) always produce
    // identical output — no hidden state, no cross-invocation persistence.
    @Test func sameInputsProduceSameLabels() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define r1 (jump-labels-assign '(t1 t2 t3) '("a" "s" "d") '("a") '("q" "w")))
          (define r2 (jump-labels-assign '(t1 t2 t3) '("a" "s" "d") '("a") '("q" "w")))
        """)
        #expect(try engine.evaluate("(equal? r1 r2)") == .true)
    }

    // The label SEQUENCE tracks target POSITION, not target identity: the
    // same targets in a different order get the same labels reassigned by
    // position, each target carrying whichever label its new position earns.
    @Test func labelSequenceTracksPositionNotTargetIdentity() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define ra (jump-labels-assign '(t1 t2 t3) '("a" "s" "d") '() '()))
          (define rb (jump-labels-assign '(t3 t2 t1) '("a" "s" "d") '() '()))
        """)
        #expect(try engine.evaluate("(equal? (map car ra) (map car rb))") == .true)
        #expect(try engine.evaluate("(equal? (map cdr ra) '(t1 t2 t3))") == .true)
        #expect(try engine.evaluate("(equal? (map cdr rb) '(t3 t2 t1))") == .true)
    }

    // Stress case: every single/leader letter ends up escalated (leader-alphabet
    // == single-alphabet exactly), forcing the whole single pool to sacrifice
    // itself for two-key duty across 13 targets. Exercises escalation-minimality
    // (exactly 3 leaders — the fewest that reach capacity 13) and prefix-freedom
    // together via the generic validator.
    @Test func stressEscalationStaysPrefixFree() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign
                           '(t01 t02 t03 t04 t05 t06 t07 t08 t09 t10 t11 t12 t13)
                           '("a" "s" "d") '("a" "s" "d")
                           '("q" "w" "e" "r" "t")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map car result)
                  '("aq" "aw" "ae" "ar" "at" "sq" "sw" "se" "sr" "st" "dq" "dw" "de"))
        """) == .true)
        #expect(try engine.evaluate("(all-prefix-free? (map car result))") == .true)
    }

    // A mixed scenario (some overlapping, some free leaders) checked purely
    // via the generic prefix-free property, independent of the exact expected
    // sequence already pinned down by the tests above.
    @Test func mixedLeadersRemainPrefixFree() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define result (jump-labels-assign
                           '(t1 t2 t3 t4 t5 t6 t7 t8)
                           '("a" "s" "d") '("a" "q") '("1" "2" "3")))
        """)
        #expect(try engine.evaluate("(all-prefix-free? (map car result))") == .true)
    }
}
