import Testing

@testable import Modaliser

/// Tests for `(modaliser jump-list)` (jump-list-k4) — the lowering of a jump
/// label assignment onto FSM edges and provided states, extracted from
/// `(modaliser wms paneru)`'s strip provider when the VSCode project panel
/// needed the same shape over a different row source.
///
/// **This suite exists because the machinery it covers fails silently.** A
/// prefix state minted with the wrong id garbles a breadcrumb, one minted
/// without its own provider makes a second key resolve to a state nobody
/// minted, and one minted without a payload narrows into a blank screen. None
/// of those raise. Paneru's own suite pins them through paneru's composition;
/// this one pins them through a *synthetic* one, so the properties are stated
/// once against the machinery itself rather than only against a caller.
///
/// **Nothing here reaches outward and nothing needs a seam.**
/// `jump-list-provider-result` is a pure function: it *constructs* states
/// whose entry thunks are never fired, so the injected `'action` below can be
/// a closure over a counter and still record zero calls.
@Suite("(modaliser jump-list) library")
struct ModaliserJumpListLibraryTests {

    // MARK: - Fixtures

    /// An engine with the library imported and a synthetic caller bound: three
    /// targets, and the three functions a caller injects.
    ///
    /// The targets are deliberately *not* windows. jump-list knows nothing of
    /// windows, and a fixture shaped like one would let a window-shaped
    /// assumption leak back in unnoticed — so a target here is an id, a name,
    /// and a `live` flag standing in for whatever makes a real row actionable.
    /// `t3` is inert, which is the drop case.
    private func engineWithCaller() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser jump-list) (modaliser fsm) (modaliser util))")
        try engine.evaluate("""
          (define (mk id name live) (list (cons 'id id) (cons 'name name) (cons 'live live)))
          (define T1 (mk 1 "one"   #t))
          (define T2 (mk 2 "two"   #t))
          (define T3 (mk 3 "three" #f))   ; inert: no action, so no edge
          (define T4 (mk 4 "four"  #t))

          (define (STATE-ID t) (string-append "demo/" (number->string (cdr (assoc 'id t)))))
          (define (ACTION t)
            (and (cdr (assoc 'live t))
                 (lambda () 'fired)))
          ;; A minimal block spec — jump-list reads only its 'type, and closes
          ;; over the pairs it is handed so the narrowed rows are assertable.
          (define (BLOCK pairs)
            (list (cons 'type 'demo-block)
                  (cons 'on-render-fn (lambda () (list (cons 'rows pairs))))))

          (define (lower assigned owner-id panel-label)
            (jump-list-provider-result assigned owner-id panel-label
              'state-id STATE-ID 'action ACTION 'block BLOCK))
        """)
        return engine
    }

    // MARK: - Surface

    /// Both exports bind. Each is public contract the moment a library or a
    /// test can reference it.
    @Test func exportsResolveAsProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser jump-list))")
        for name in ["jump-list-provider-result", "jump-list-prefix-state-id"] {
            #expect(
                try engine.evaluate("(procedure? \(name))") == .true,
                "expected \(name) to be exported")
        }
    }

    /// The prefix state's id is OWNER-ID + "/" + leader and follows whatever
    /// owner id the engine supplied, rather than a literal baked in here.
    /// `modal-current-path` derives a breadcrumb segment by `substring`ing the
    /// parent's id off the child's, so any other shape garbles it or raises.
    @Test func prefixStateIdIsTheOwnersIdSlashTheLeader() throws {
        let engine = try engineWithCaller()
        #expect(
            try engine.evaluate("(jump-list-prefix-state-id \"global/v\" \"a\")")
                == .string("global/v/a"))
        #expect(
            try engine.evaluate("(jump-list-prefix-state-id \"elsewhere\" \"q\")")
                == .string("elsewhere/q"))
    }

    // MARK: - Single-key labels

    /// A one-key label becomes a direct edge to a Terminal state named by the
    /// caller's own `'state-id`, and the two agree — the edge's target IS the
    /// state's id, which is the join that makes a keypress reach a row.
    @Test func aSingleKeyLabelBecomesADirectEdgeToItsTerminalState() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define R (lower (list (cons "a" T1) (cons "s" T2)) "global/v" "Jump"))
          (define EDGES  (cdr (assoc 'edges  R)))
          (define STATES (cdr (assoc 'states R)))
        """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES) (list "a" "s"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                      (list "demo/1" "demo/2"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (s) (cdr (assoc 'id s))) STATES)
                      (list "demo/1" "demo/2"))
            """) == .true)
        // Terminal: no edges of its own, so firing halts the engine and the
        // modal exits — which is what a jump means.
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges (car STATES))))") == .true)
    }

    /// An entry thunk is *constructed*, never called, during lowering. This is
    /// what lets every test in this file run with no seam beneath it, and what
    /// makes the same true of every caller's provider test.
    @Test func loweringConstructsEntryThunksWithoutFiringThem() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define FIRED 0)
          (define (COUNTING t) (and (cdr (assoc 'live t))
                                    (lambda () (set! FIRED (+ FIRED 1)))))
          (jump-list-provider-result (list (cons "a" T1) (cons "sd" T2))
            "global/v" "Jump" 'state-id STATE-ID 'action COUNTING 'block BLOCK)
        """)
        #expect(try engine.evaluate("FIRED") == .fixnum(0))
    }

    // MARK: - Dropping, and what dropping does not touch

    /// Two kinds of target contribute no edge: an UNLABELLED one (#f, past the
    /// alphabets' exhaustion) and an INERT one (the caller's `'action`
    /// answered #f). Both are dropped from the edge set and from nothing else
    /// — the assignment is untouched, so the caller's listing still draws them
    /// and every label below keeps its place.
    @Test func unlabelledAndInertTargetsGetNoEdgeAndRenumberNothing() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define A (list (cons "a" T1) (cons "s" T3) (cons #f T4) (cons "f" T2)))
          (define R (lower A "global/v" "Jump"))
          (define EDGES (cdr (assoc 'edges R)))
        """)
        // T3 is inert and T4 unlabelled, so only a and f survive — and "f" is
        // still "f", not renumbered up into the gap T3 left.
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES) (list "a" "f"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                      (list "demo/1" "demo/2"))
            """) == .true)
        #expect(try engine.evaluate("(length (cdr (assoc 'states R)))") == .fixnum(2))
    }

    /// A leader whose every second key is dropped contributes no group at all,
    /// so the leader key stays dead rather than narrowing into an empty
    /// listing — a state with rows nobody can reach is worse than no state.
    @Test func aLeaderWithNoLiveSecondKeyMintsNoPrefixState() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define R (lower (list (cons "qa" T3) (cons "qs" T3)) "global/v" "Jump"))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges  R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
    }

    // MARK: - Two-key labels and the narrowing prefix state

    /// A two-key label yields ONE edge per leader — not one per target — and
    /// that edge targets the prefix state's id. Two targets under `q` and one
    /// under `w` give exactly two leader edges, in first-seen leader order.
    @Test func twoKeyLabelsCollapseToOneEdgePerLeaderInFirstSeenOrder() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define R (lower (list (cons "qa" T1) (cons "wa" T2) (cons "qs" T4))
                           "global/v" "Jump"))
          (define EDGES (cdr (assoc 'edges R)))
        """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES) (list "q" "w"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                      (list "global/v/q" "global/v/w"))
            """) == .true)
    }

    /// The prefix state's four non-negotiable properties, asserted together
    /// because each fails silently on its own:
    ///
    /// 1. its `'up` edge targets the owner, or backspace does not un-narrow;
    /// 2. its second-key edges target the Terminal states of its OWN group,
    ///    in that group's own second-key order;
    /// 3. it carries its own `'provider`, re-minting exactly those states —
    ///    provided states are Visit-scoped, and stepping in begins a new Visit,
    ///    so without this the second key resolves to a state nobody minted;
    /// 4. its `'payload` carries the two-layer node shape the panel-grid
    ///    renderer resolves (ADR-0011), naming the block by the `'type` the
    ///    caller's own block spec declared.
    @Test func thePrefixStateUnNarrowsRemintsAndDrawsItsOwnGroup() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define R (lower (list (cons "qa" T1) (cons "qs" T2) (cons "wa" T4))
                           "global/v" "Jump"))
          (define Q (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/v/q"))
                          (cdr (assoc 'states R))))
          (define Q-EDGES (cdr (assoc 'edges Q)))
        """)
        #expect(try engine.evaluate("Q") != .false)

        // 1 — the up edge climbs back to the owner the engine supplied.
        #expect(
            try engine.evaluate("""
              (cdr (assoc 'target (find (lambda (e) (eq? (cdr (assoc 'trigger e)) 'up))
                                        Q-EDGES)))
            """) == .string("global/v"))

        // 2 — second keys, this group's only, in its own order.
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e)))
                           (filter (lambda (e) (string? (cdr (assoc 'trigger e)))) Q-EDGES))
                      (list "a" "s"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'target e)))
                           (filter (lambda (e) (string? (cdr (assoc 'trigger e)))) Q-EDGES))
                      (list "demo/1" "demo/2"))
            """) == .true)

        // 3 — the re-mint provides exactly the states those edges name, and
        // takes no second gather to do it (the pairs are closed over).
        try engine.evaluate("""
          (define PROVIDED (cdr (assoc 'states ((cdr (assoc 'provider Q)) "global/v/q"))))
        """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (s) (cdr (assoc 'id s))) PROVIDED)
                      (list "demo/1" "demo/2"))
            """) == .true)

        // 4 — the payload's two layers, and the block named by its own type.
        try engine.evaluate("(define P (cdr (assoc 'payload Q)))")
        #expect(
            try engine.evaluate("""
              (equal? (cdr (assoc 'type (car (cdr (assoc 'children P))))) 'demo-block)
            """) == .true)
        #expect(
            try engine.evaluate("""
              (let ((panel (car (cdr (assoc 'panels (cdr (assoc 'display P)))))))
                (and (equal? (cdr (assoc 'label panel)) "Jump")
                     (equal? (cdr (assoc 'block (cdr (assoc 'rows panel)))) 'demo-block)))
            """) == .true)
    }

    /// The narrowed listing draws the same targets the second-key edges
    /// dispatch to — the block is closed over the survivor pairs the owner's
    /// lowering already computed, so rows and labels cannot disagree and no
    /// second gather happens.
    @Test func theNarrowedBlockDrawsExactlyItsGroupsSurvivors() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("""
          (define R (lower (list (cons "qa" T1) (cons "qs" T3) (cons "qd" T2))
                           "global/v" "Jump"))
          (define Q (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/v/q"))
                          (cdr (assoc 'states R))))
          (define ROWS ((cdr (assoc 'on-render-fn
                                    (car (cdr (assoc 'children (cdr (assoc 'payload Q)))))))))
        """)
        // T3 was inert and never entered the group, so it is neither an edge
        // nor a narrowed row.
        #expect(
            try engine.evaluate("""
              (equal? (map car (cdr (assoc 'rows ROWS))) (list "a" "d"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (p) (cdr (assoc 'name (cdr p)))) (cdr (assoc 'rows ROWS)))
                      (list "one" "two"))
            """) == .true)
    }

    /// An empty assignment lowers to nothing rather than raising. The provider
    /// runs on the come-to-rest path, so a raise here is a leader press that
    /// errors instead of opening a screen.
    @Test func anEmptyAssignmentLowersToNoEdgesAndNoStates() throws {
        let engine = try engineWithCaller()
        try engine.evaluate("(define R (lower '() \"global/v\" \"Jump\"))")
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges  R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
    }
}
