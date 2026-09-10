import Testing

@testable import Modaliser

/// Tests for `(modaliser jump-list)`'s provider composition
/// (vscode-part-panels-k7, docs/specs/vscode-window-parts.md decision 7) — the
/// merge that lets a screen carry more than one labelled panel on its single
/// `'provider` slot.
///
/// **This suite exists because the engine checks none of it.** A provider's
/// edges are folded in with the owner state's own by plain append; a key is
/// resolved by finding the *first* matching live edge; provided states go into
/// a table keyed by id and a duplicate is last-wins. So two panels sharing a
/// key is not an error anywhere — it is a terminal's label focusing a project,
/// silently, and only for as long as nobody notices.
///
/// **The targets here are deliberately neither editors nor terminals.** The
/// merge is source-independent, and a VSCode-shaped fixture would let a
/// VSCode-shaped assumption leak into machinery that must not have one.
///
/// **Almost everything lands on `jump-list-validate-composition`, which is
/// pure**, and that placement is the decision rather than a convenience. An
/// earlier draft of this design let a caller pass the owner's edges and the
/// registered state ids in as optional arguments so a test could supply them —
/// which meant a user's config, being Scheme calling the same exported
/// procedure, could hand in two empty readers and switch the invariant off
/// while still appearing to compose safely. The split at the purity line
/// removes that: the public wrapper asks the graph itself and takes no switch,
/// and the half worth testing takes every fact as data.
@Suite("(modaliser jump-list) composition")
struct ModaliserJumpListCompositionTests {

    // MARK: - Fixtures

    /// An engine with the library imported and two synthetic provider results
    /// bound, plus the helpers to build more.
    ///
    /// `result` builds an `((edges . …) (states . …))` from bare key/id lists,
    /// so a test states only what it is about. `edge` and `provided-state` are
    /// the FSM's own constructors, so these are the same values a real
    /// provider returns rather than a hand-rolled lookalike.
    private func engineWithResults() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser jump-list)
                  (only (modaliser fsm)
                        edge provided-state fsm-make-graph fsm-graph-state!
                        fsm-install-graph!))
          (define (result keys ids)
            (list (cons 'edges  (map (lambda (k) (edge k (string-append "s/" k))) keys))
                  (cons 'states (map (lambda (i) (provided-state i)) ids))))
          """)
        return engine
    }

    /// The error message a raising call produced, or nil if it did not raise.
    private func raiseMessage(_ engine: SchemeEngine, _ form: String) -> String? {
        do {
            _ = try engine.evaluate(form)
            return nil
        } catch {
            return "\(error)"
        }
    }

    // MARK: - The surface

    @Test func exportsResolveAsProcedures() throws {
        let engine = try engineWithResults()
        #expect(try engine.evaluate("(procedure? jump-list-compose-providers)") == .true)
        #expect(try engine.evaluate("(procedure? jump-list-validate-composition)") == .true)
    }

    // MARK: - The clean merge

    /// Disjoint contributors merge to the concatenation of both edge and state
    /// lists, in argument order. Order is the contract, not an accident: the
    /// engine resolves a key by first match, so a merge that reordered would
    /// change which panel wins a collision it failed to catch.
    @Test func disjointContributorsConcatenateInArgumentOrder() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (define M (jump-list-validate-composition
                      (list (result '("a" "s") '("x/1" "x/2"))
                            (result '("h" "j") '("y/1" "y/2")))
                      '("Projects" "Editors")
                      '() '()))
          """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) (cdr (assoc 'edges M)))
                      (list "a" "s" "h" "j"))
              """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (s) (cdr (assoc 'id s))) (cdr (assoc 'states M)))
                      (list "x/1" "x/2" "y/1" "y/2"))
              """) == .true)
    }

    /// A single contributor is the degenerate case and must not raise — a
    /// screen may compose one panel today and two tomorrow without the merge
    /// becoming a special case at either end.
    @Test func oneContributorMergesToItself() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (define M (jump-list-validate-composition
                      (list (result '("a") '("x/1"))) '("Projects") '() '()))
          """)
        #expect(try engine.evaluate("(= 1 (length (cdr (assoc 'edges M))))") == .true)
        #expect(try engine.evaluate("(= 1 (length (cdr (assoc 'states M))))") == .true)
    }

    // MARK: - The four raises

    /// Two panels claiming one key. The engine would bind it to whichever
    /// contributed first, so the user presses a terminal's label and focuses a
    /// project — a silent wrong dispatch, which is the whole reason this
    /// raises rather than dropping.
    @Test func twoContributorsSharingAKeyRaise() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("a" "j") '("x/1"))
                    (result '("h" "j") '("y/1")))
              '("Terminals" "Editors") '() '())
            """)
        #expect(message != nil)
    }

    /// Two panels minting one state id. A provided state goes into a table
    /// keyed by id, so the second silently replaces the first and one panel's
    /// label runs the other panel's action.
    @Test func twoContributorsSharingAStateIdRaise() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("a") '("shared/1"))
                    (result '("h") '("shared/1")))
              '("Terminals" "Editors") '() '())
            """)
        #expect(message != nil)
    }

    /// **The likelier collision, and the one the first design missed.** A
    /// promoted leader landing on a key the owner state already declares
    /// dispatches to the *static* edge — first live match wins — so the row's
    /// label silently does something else entirely. It is likelier than a
    /// panel-panel collision because the screen's own keys are already spoken
    /// for.
    @Test func aContributorCollidingWithTheOwnersStaticEdgeRaises() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("p") '("x/1")))
              '("Editors")
              (list (edge "p" "global/file-finder"))
              '())
            """)
        #expect(message != nil)
    }

    /// A provided state shadows a permanently registered state of the same id,
    /// first-lookup-wins, with nothing checked anywhere.
    @Test func aContributorCollidingWithARegisteredStateIdRaises() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("a") '("global/settings")))
              '("Editors") '() '("global" "global/settings"))
            """)
        #expect(message != nil)
    }

    // MARK: - What the raise says

    /// **The raise names the contributors, not their positions.** The merge
    /// receives opaque procedures and nothing recoverable from a closure says
    /// which of the user's panels owns the colliding key, so the name is
    /// supplied at the call site — the panel's own, out of the user's config.
    /// "Terminals and Editors both claim j" is a repair; "provider 1 and
    /// provider 2" is a puzzle.
    ///
    /// The names being the caller's is also what keeps this library free of
    /// authored labels (ADR-0021).
    @Test func theRaiseNamesBothContributorsAndTheKey() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("j") '("x/1"))
                    (result '("j") '("y/1")))
              '("Terminals" "Editors") '() '())
            """)
        let text = try #require(message)
        #expect(text.contains("Terminals"))
        #expect(text.contains("Editors"))
        #expect(text.contains("j"))
        // And no ordinal stand-in for a name.
        #expect(!text.contains("provider 1"))
    }

    /// A collision against the owner names the panel and says the screen owns
    /// the other side, so the user knows which of the two to move.
    @Test func theOwnerRaiseNamesThePanelAndTheScreen() throws {
        let engine = try engineWithResults()
        let message = raiseMessage(
            engine,
            """
            (jump-list-validate-composition
              (list (result '("p") '("x/1")))
              '("Editors") (list (edge "p" "global/file-finder")) '())
            """)
        let text = try #require(message)
        #expect(text.contains("Editors"))
        #expect(text.contains("screen"))
        #expect(text.contains("p"))
    }

    // MARK: - What is compared, and how

    /// **Nothing is normalised, because the engine normalises nothing.** The
    /// graph's edge table and the visit's provided-state table are both plain
    /// `equal?`-keyed hash tables, so the string `"x"` and the symbol `x` are
    /// two different states there and must be two different states here.
    /// Collapsing them would invent a collision the engine does not have.
    @Test func aStringIdAndASymbolIdAreDifferentIds() throws {
        let engine = try engineWithResults()
        #expect(
            raiseMessage(
                engine,
                """
                (jump-list-validate-composition
                  (list (list (cons 'edges '()) (cons 'states (list (provided-state "x")))))
                  '("Editors") '() '(x))
                """) == nil)
    }

    /// A contributor colliding with *itself* is a real defect and is reported.
    /// A contributor need not be one of ours — the merge takes any Edge
    /// provider — so "our own lowering cannot produce this" is not a reason to
    /// skip the check.
    @Test func aContributorCollidingWithItselfRaises() throws {
        let engine = try engineWithResults()
        #expect(
            raiseMessage(
                engine,
                """
                (jump-list-validate-composition
                  (list (result '("a" "a") '("x/1"))) '("Editors") '() '())
                """) != nil)
    }

    /// An absent `'edges` or `'states` key is an empty one, not a crash. A
    /// contributor that had nothing to contribute this come-to-rest — a panel
    /// whose window has no terminals — must merge cleanly.
    @Test func aContributorWithNothingToContributeMergesCleanly() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (define M (jump-list-validate-composition
                      (list '() (result '("h") '("y/1")))
                      '("Terminals" "Editors") '() '()))
          """)
        #expect(try engine.evaluate("(= 1 (length (cdr (assoc 'edges M))))") == .true)
    }

    // MARK: - The impure wrapper

    /// `jump-list-compose-providers` calls each contributor with the owner id
    /// the engine handed it, and merges the results. One test, because
    /// everything that can be wrong in it is in the validator above — which is
    /// the point of splitting it there.
    @Test func composeProvidersCallsEachContributorWithTheOwnerId() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (fsm-install-graph!
            (let ((g (fsm-make-graph)))
              (fsm-graph-state! g "global/vscode")
              g))
          (define seen '())
          (define P (jump-list-compose-providers
                      "Terminals" (lambda (owner) (set! seen (cons owner seen))
                                          (result '("t") '("vt/1")))
                      "Editors"   (lambda (owner) (set! seen (cons owner seen))
                                          (result '("h") '("ve/1")))))
          (define M (P "global/vscode"))
          """)
        #expect(try engine.evaluate("(equal? seen '(\"global/vscode\" \"global/vscode\"))") == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) (cdr (assoc 'edges M)))
                      (list "t" "h"))
              """) == .true)
    }

    /// **The wrapper asks the graph itself, and there is no argument that can
    /// stop it.** A contributor colliding with a static edge of the *installed*
    /// graph raises through the public entry point — which is the property that
    /// makes the check structural rather than a discipline a config could
    /// opt out of.
    @Test func composeProvidersReachesTheInstalledGraphsStaticEdges() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (fsm-install-graph!
            (let ((g (fsm-make-graph)))
              (fsm-graph-state! g "global/vscode" (edge "p" "global/vscode/finder"))
              (fsm-graph-state! g "global/vscode/finder")
              g))
          (define P (jump-list-compose-providers
                      "Editors" (lambda (owner) (result '("p") '("ve/1")))))
          """)
        let text = try #require(raiseMessage(engine, "(P \"global/vscode\")"))
        #expect(text.contains("Editors"))
        #expect(text.contains("screen"))
    }

    /// An owner id naming no registered state contributes no static edges
    /// rather than raising — a screen built entirely from provided states is
    /// the empty-owner-edges case, not a special one.
    @Test func anUnregisteredOwnerIdContributesNoStaticEdges() throws {
        let engine = try engineWithResults()
        try engine.evaluate("""
          (fsm-install-graph! (fsm-make-graph))
          (define P (jump-list-compose-providers
                      "Editors" (lambda (owner) (result '("p") '("ve/1")))))
          (define M (P "global/nowhere"))
          """)
        #expect(try engine.evaluate("(= 1 (length (cdr (assoc 'edges M))))") == .true)
    }

    /// A name with no provider after it is a call-site typo, and it raises at
    /// composition time rather than handing back a provider that will fail on
    /// the first keypress.
    @Test func aDanglingNameRaisesAtCompositionTime() throws {
        let engine = try engineWithResults()
        #expect(
            raiseMessage(
                engine,
                """
                (jump-list-compose-providers "Terminals" (lambda (o) (result '() '())) "Editors")
                """) != nil)
    }
}
