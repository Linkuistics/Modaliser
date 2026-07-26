import Foundation
import Testing
@testable import Modaliser

// Unit tests for (modaliser configuration) — the Fragment model and the
// pure `configuration` merge (config-value-core-k6, ADR-0018,
// docs/specs/configuration-value.md). First tests on the pure
// configuration-pipeline seam: fragments in → Configuration value or a
// decodable error. Covers the uniform keyed merge (diamond dedup via
// eq?, same-key conflicts), setting duplicates, tree-scope key
// normalization, and walk hoisting on hand-built tree-bearing values.
@Suite("(modaliser configuration) library")
struct ModaliserConfigurationLibraryTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (scheme base) (scheme cxr) (modaliser configuration))")
        // Decodable-error helper: run THUNK, returning its error's
        // irritants — (code detail …) — or 'no-error when it succeeds.
        try engine.evaluate("""
          (define (catch-irritants thunk)
            (guard (e (#t (error-object-irritants e)))
              (thunk)
              'no-error))
        """)
        return engine
    }

    // ── Contribution constructors ───────────────────────────────────

    @Test func constructorsReturnTaggedContributions() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define t-node '((kind . group) (key . "") (children . ())))
          (define t (tree 'global t-node))
          (define b (backend 'iterm 'record-stub))
          (define c (context "herdr" 'tree 'herdr-tree 'backend 'herdr))
          (define c2 (context "nvim" 'tree 'nvim-tree))
          (define s (setting 'theme 'dark))
        """)
        #expect(try engine.evaluate("(equal? t (list 'tree 'global t-node))") == .true)
        #expect(try engine.evaluate("(equal? b '(backend iterm record-stub))") == .true)
        #expect(try engine.evaluate("""
          (equal? c '(context "herdr" ((tree . herdr-tree) (backend . herdr))))
        """) == .true)
        // The optional backend reference is absent, not #f, when unsupplied.
        #expect(try engine.evaluate("""
          (equal? c2 '(context "nvim" ((tree . nvim-tree))))
        """) == .true)
        #expect(try engine.evaluate("(equal? s '(setting theme dark))") == .true)
    }

    @Test func settingsConstructorsAreSettingContributions() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define ls (leaders (leader 'global 49 'modifiers '(shift))
                              (leader 'local 36)))
          (define od (overlay-delay 0.5))
        """)
        #expect(try engine.evaluate("(eq? (car ls) 'setting)") == .true)
        #expect(try engine.evaluate("(eq? (cadr ls) 'leaders)") == .true)
        #expect(try engine.evaluate("(= 2 (length (caddr ls)))") == .true)
        #expect(try engine.evaluate("""
          (equal? (car (caddr ls))
                  '((mode . global) (keycode . 49)
                    (modifiers . (shift)) (arm-when-frontmost . ())))
        """) == .true)
        #expect(try engine.evaluate("(equal? od '(setting overlay-delay 0.5))") == .true)
    }

    @Test func constructorValidationErrorsAreDecodable() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (leader 'nope 49)))
                  '(invalid-leader-mode nope))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (context "x" 'backend 'b)))
                  '(invalid-context-entry "x"))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (overlay-delay -1)))
                  '(invalid-overlay-delay -1))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (tree 42 '((kind . group)))))
                  '(invalid-tree-scope 42))
        """) == .true)
    }

    // ── Flattening and the assembled value ──────────────────────────

    @Test func configurationFlattensNestedFragments() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define t-node '((kind . group) (key . "") (children . ())))
          ;; A constructor-style fragment: one bag delivering several
          ;; contributions, nested one level deeper on the way in.
          (define bag (list (tree 'global t-node)
                            (backend 'iterm 'iterm-record)))
          (define cfg (configuration
                        (list bag (context "herdr" 'tree 'herdr-tree 'backend 'herdr))
                        (overlay-delay 0.5)))
        """)
        #expect(try engine.evaluate("(configuration? cfg)") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'global) t-node)") == .true)
        #expect(try engine.evaluate("(eq? (configuration-backend-ref cfg 'iterm) 'iterm-record)") == .true)
        #expect(try engine.evaluate("""
          (equal? (configuration-context-ref cfg "herdr")
                  '((tree . herdr-tree) (backend . herdr)))
        """) == .true)
        #expect(try engine.evaluate("(= (configuration-setting-ref cfg 'overlay-delay) 0.5)") == .true)
        // Unset settings fall to the caller's default (engine defaults at handoff).
        #expect(try engine.evaluate("(eq? (configuration-setting-ref cfg 'theme 'fallback) 'fallback)") == .true)
    }

    @Test func emptyConfigurationIsValid() throws {
        let engine = try loaded()
        try engine.evaluate("(define cfg (configuration))")
        #expect(try engine.evaluate("(configuration? cfg)") == .true)
        #expect(try engine.evaluate("(null? (configuration-trees cfg))") == .true)
        #expect(try engine.evaluate("(eq? #f (configuration-setting-ref cfg 'overlay-delay))") == .true)
    }

    @Test func invalidItemErrorsDecodably() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (configuration 42)))
                  '(invalid-contribution 42))
        """) == .true)
        // A malformed contribution (tag arity wrong) is rejected, not
        // silently treated as a nested fragment.
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (configuration (list (list 'tree "x")))))
                  '(invalid-contribution (tree "x")))
        """) == .true)
    }

    // ── The uniform merge rule ──────────────────────────────────────

    @Test func diamondMergesSilently() throws {
        let engine = try loaded()
        // One fragment reached via two composition paths: the SAME
        // contribution objects arrive twice and merge to one entry each.
        try engine.evaluate("""
          (define t-node '((kind . group) (key . "") (children . ())))
          (define shared (list (tree 'shared t-node) (backend 'b0 'rec)))
          (define cfg (configuration shared shared))
        """)
        #expect(try engine.evaluate("(= 1 (length (configuration-trees cfg)))") == .true)
        #expect(try engine.evaluate("(= 1 (length (configuration-backends cfg)))") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'shared) t-node)") == .true)
    }

    @Test func sameKeyConflictErrorsDecodably() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define ta '((kind . group) (label . "A") (children . ())))
          (define tb '((kind . group) (label . "B") (children . ())))
        """)
        #expect(try engine.evaluate("""
          (equal? (catch-irritants
                    (lambda () (configuration (tree 'global ta) (tree 'global tb))))
                  '(duplicate-key tree global))
        """) == .true)
    }

    @Test func settingDuplicatesError() throws {
        let engine = try loaded()
        // Two separately constructed contributions for the same setting
        // are a conflict — no override, no last-wins.
        #expect(try engine.evaluate("""
          (equal? (catch-irritants
                    (lambda () (configuration (overlay-delay 0.5) (overlay-delay 0.7))))
                  '(duplicate-key setting overlay-delay))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (catch-irritants
                    (lambda () (configuration (leaders (leader 'global 49))
                                              (leaders (leader 'local 36)))))
                  '(duplicate-key setting leaders))
        """) == .true)
    }

    @Test func treeScopeSymbolAndStringSpellingsCollide() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define ta '((kind . group) (label . "A") (children . ())))
          (define tb '((kind . group) (label . "B") (children . ())))
        """)
        // 'global and "global" name the same scope (the engine keys
        // trees by string), so distinct bodies under the two spellings
        // conflict …
        #expect(try engine.evaluate("""
          (equal? (catch-irritants
                    (lambda () (configuration (tree 'global ta) (tree "global" tb))))
                  '(duplicate-key tree "global"))
        """) == .true)
        // … and a single registration is findable by either spelling.
        try engine.evaluate("(define cfg (configuration (tree 'global ta)))")
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg \"global\") ta)") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'global) ta)") == .true)
    }

    // ── Walk hoisting on hand-built tree-bearing values ─────────────

    @Test func hoistingLiftsCarriedTreeIntoTheTreeSet() throws {
        let engine = try loaded()
        // The shape a walk's splice takes once splices survive to the
        // merge (dsl-purification): a splice node carrying its own tree.
        try engine.evaluate("""
          (define walk-tree '((kind . group) (key . "") (children . ())))
          (define walk-splice (list (cons 'kind 'splice)
                                    (cons 'tree (cons 'w1 walk-tree))
                                    (cons 'children '())))
          (define screen-a (list (cons 'kind 'group) (cons 'key "")
                                 (cons 'children (list walk-splice))))
          (define cfg (configuration (tree 'a screen-a)))
        """)
        #expect(try engine.evaluate("(= 2 (length (configuration-trees cfg)))") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'w1) walk-tree)") == .true)
        // The authored body is untouched — the splice still carries its
        // tree in place (expansion is lowering's business, not the merge's).
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'a) screen-a)") == .true)
    }

    @Test func hoistingDiamondDedups() throws {
        let engine = try loaded()
        // The same walk spliced into two screens contributes its mode
        // tree once — identity dedup, no conflict.
        try engine.evaluate("""
          (define walk-tree '((kind . group) (key . "") (children . ())))
          (define walk-splice (list (cons 'kind 'splice)
                                    (cons 'tree (cons 'w1 walk-tree))
                                    (cons 'children '())))
          (define screen-a (list (cons 'kind 'group) (cons 'children (list walk-splice))))
          (define screen-b (list (cons 'kind 'group) (cons 'children (list walk-splice))))
          (define cfg (configuration (tree 'a screen-a) (tree 'b screen-b)))
        """)
        #expect(try engine.evaluate("(= 3 (length (configuration-trees cfg)))") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'w1) walk-tree)") == .true)
    }

    @Test func hoistingConflictErrorsDecodably() throws {
        let engine = try loaded()
        // Two DIFFERENT trees claiming the same walk scope conflict,
        // same rule as top-level contributions.
        #expect(try engine.evaluate("""
          (equal?
            (catch-irritants
              (lambda ()
                (let* ((wa '((kind . group) (label . "A") (children . ())))
                       (wb '((kind . group) (label . "B") (children . ())))
                       (sa (list (cons 'kind 'splice) (cons 'tree (cons 'w1 wa))
                                 (cons 'children '())))
                       (sb (list (cons 'kind 'splice) (cons 'tree (cons 'w1 wb))
                                 (cons 'children '()))))
                  (configuration
                    (tree 'a (list (cons 'kind 'group) (cons 'children (list sa))))
                    (tree 'b (list (cons 'kind 'group) (cons 'children (list sb))))))))
            '(duplicate-key tree w1))
        """) == .true)
    }

    @Test func hoistingRecursesIntoCarriedTrees() throws {
        let engine = try loaded()
        // A carried tree whose own body carries another tree: both
        // hoist — the tree set closes transitively.
        try engine.evaluate("""
          (define inner '((kind . group) (children . ())))
          (define inner-splice (list (cons 'kind 'splice)
                                     (cons 'tree (cons 'w2 inner))
                                     (cons 'children '())))
          (define outer (list (cons 'kind 'group)
                              (cons 'children (list inner-splice))))
          (define outer-splice (list (cons 'kind 'splice)
                                     (cons 'tree (cons 'w1 outer))
                                     (cons 'children '())))
          (define scr (list (cons 'kind 'group)
                            (cons 'children (list outer-splice))))
          (define cfg (configuration (tree 'root scr)))
        """)
        #expect(try engine.evaluate("(= 3 (length (configuration-trees cfg)))") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'w1) outer)") == .true)
        #expect(try engine.evaluate("(eq? (configuration-tree-ref cfg 'w2) inner)") == .true)
    }

    // ── The real DSL feeds the merge (dsl-purification-k9) ──────────

    @Test func walkSplicedIntoTwoScreensContributesOneModeTree() throws {
        let engine = try loaded()
        // The leaf's proof: one walk, spliced into TWO screens built by the
        // real sugar, reaches the merge as tree contributions and lowers to
        // ONE mode tree — and the whole value closes (the entry keys' 'next
        // cross edges resolve against the hoisted tree).
        try engine.evaluate("""
          (import (modaliser fsm)
                  (modaliser event-dispatch)
                  (modaliser dsl))
          (define act (lambda () 'ok))
          (define nav (walk 'shared-walk "Nav" (key "h" "Left" act)))
          (define s1 (screen 'scr-one nav (panel "P" (key "c" "C" act))))
          (define s2 (screen 'scr-two nav))
          (define cfg (configuration s1 s2))
        """)
        // Exactly three trees: the two screens plus ONE hoisted mode tree.
        #expect(try engine.evaluate("(= 3 (length (configuration-trees cfg)))") == .true)
        #expect(try engine.evaluate("(pair? (configuration-tree-ref cfg 'shared-walk))") == .true)
        // The pure lower closes over the hoisted tree (fsm-graph value out).
        try engine.evaluate("(import (modaliser fsm))")
        #expect(try engine.evaluate("(fsm-graph? (lower-configuration cfg))") == .true)
    }
}
