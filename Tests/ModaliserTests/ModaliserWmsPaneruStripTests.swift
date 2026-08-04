import Testing

@testable import Modaliser

/// Tests for the **Strip listing** half of `(modaliser wms paneru)`
/// (paneru-strip-list-k7, `docs/specs/paneru-window-management.md`) — the
/// parse, the id join, label lowering onto FSM edges, and the Edge provider
/// that runs the whole pipeline at come-to-rest.
///
/// The suite's ops-and-predicate sibling is `ModaliserWmsPaneruLibraryTests`.
///
/// **Two seams, and nothing else reaches outward.** `current-shell-runner`
/// (ADR-0023) answers the `paneru query state --json` call with a canned
/// payload, and `strip-provider`'s `'enumerate` option answers the window
/// enumeration with a canned list. The second is a *determinism* seam rather
/// than an isolation one: `list-current-space-windows` performs an uncached
/// accessibility sweep of every running application, so a provider test that
/// let it run would assert an edge set determined by whatever happened to be
/// open on the developer's desktop — vacuous on a quiet machine, flaky on a
/// busy one. Neither seam is bypassed anywhere below, so `focus-window` is
/// never called and no paneru daemon is contacted.
@Suite("(modaliser wms paneru) strip listing")
struct ModaliserWmsPaneruStripTests {

    // MARK: - Fixtures

    /// A `paneru query state --json` payload, shaped from one captured off the
    /// live daemon and then arranged to carry every case at once.
    ///
    /// Four things about it are deliberate:
    ///
    /// - **Two virtual workspaces both numbered 1**, exactly as the live daemon
    ///   reports them (they sit on different native workspaces). The number is
    ///   therefore not a key — `active` is — and this is the one parse rule
    ///   that fails *silently* if guessed at, listing the wrong desktop.
    /// - **The inactive workspace comes first**, so a parse that takes the head
    ///   of the array rather than searching is red here.
    /// - **Signal floats** — listed and reachable on the same terms as any
    ///   other row, since a floating window occupies no column and could never
    ///   be named by `window focus <n>` (ADR-0024).
    /// - **Obsidian is absent from the enumeration below**, giving the
    ///   unmatched-row case its own row rather than conflating it with the
    ///   floating one.
    ///
    /// Empty titles are faithful, not lazy: every window on the live strip this
    /// was captured from reported one, which is why the block leads with the app
    /// name and treats the title as trailing detail.
    private static let payload = """
      {"version":1,"timestamp":1785814812,
       "active":{"display_id":5,"native_workspace_id":3,"virtual_workspace_number":1,
                 "focused_window_id":20786,"focused_app_name":"iTerm2"},
       "virtual_workspaces":[
         {"number":1,"native_workspace_id":7,"active":false,
          "windows":[{"window_id":999,"bundle_id":"com.other","app_name":"Elsewhere",
                      "title":"Other desktop","focused":true,"floating":false}]},
         {"number":1,"native_workspace_id":3,"active":true,
          "windows":[
            {"window_id":23141,"bundle_id":"company.thebrowser.dia","app_name":"Dia",
             "title":"","focused":false,"floating":false},
            {"window_id":20786,"bundle_id":"com.googlecode.iterm2","app_name":"iTerm2",
             "title":"modaliser","focused":true,"floating":false},
            {"window_id":23552,"bundle_id":"com.tdesktop.Telegram","app_name":"Telegram",
             "title":"Thomas","focused":false,"floating":false},
            {"window_id":27020,"bundle_id":"org.whispersystems.signal-desktop",
             "app_name":"Signal","title":"","focused":false,"floating":true},
            {"window_id":310,"bundle_id":"md.obsidian","app_name":"Obsidian",
             "title":"Notes","focused":false,"floating":false}]}]}
      """

    /// A canned window enumeration in `list-current-space-windows`' own shape.
    /// It matches four of the five strip rows; **Obsidian (310) is missing**
    /// (the unmatched case) and **55555 is present but not on the strip** (an
    /// enumerated window paneru does not report, which must not become a row).
    private static let enumeration = """
      (list (list (cons 'text "Dia")      (cons 'subText "Dia")      (cons 'windowId 23141) (cons 'ownerPid 501))
            (list (cons 'text "modaliser")(cons 'subText "iTerm2")   (cons 'windowId 20786) (cons 'ownerPid 4471))
            (list (cons 'text "Thomas")   (cons 'subText "Telegram") (cons 'windowId 23552) (cons 'ownerPid 733))
            (list (cons 'text "Signal")   (cons 'subText "Signal")   (cons 'windowId 27020) (cons 'ownerPid 902))
            (list (cons 'text "Finder")   (cons 'subText "Finder")   (cons 'windowId 55555) (cons 'ownerPid 1)))
      """

    /// An engine with the library imported and the fixtures bound. No shell
    /// runner is installed — the pure functions below need none, and its
    /// absence proves they reach nothing.
    private func engineWithFixtures() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser wms paneru) (modaliser shell) (modaliser fsm) (modaliser util))
        """)
        try engine.evaluate("(define PAYLOAD \(Self.literal(Self.payload)))")
        try engine.evaluate("(define ENUM \(Self.enumeration))")
        return engine
    }

    /// A Swift string as a *Scheme source* string literal — the payload is
    /// multi-line and full of quotes, neither of which LispKit's reader accepts
    /// raw inside a literal.
    private static func literal(_ s: String) -> String {
        let escaped =
            s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Surface

    /// The listing's exports all bind. Each is public contract the moment a
    /// config or a test can reference it.
    @Test func exportsTheListingSurface() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser wms paneru))")
        for name in [
            "strip-provider", "strip-listing",
            "parse-strip-windows", "join-strip-targets",
            "strip-focus-choice", "strip-provider-result",
        ] {
            #expect(
                try engine.evaluate("(procedure? \(name))") == .true,
                "expected \(name) to be exported")
        }
    }

    // MARK: - The parse (test seam 4 — direct call, no seam)

    /// The active workspace is selected by its `active` flag, not by matching
    /// `active.virtual_workspace_number` — the live daemon reports two
    /// workspaces both numbered 1, so the number is not a key. The inactive one
    /// leads the array here, so a head-of-array parse yields "Elsewhere".
    @Test func parseSelectsTheActiveWorkspaceNotTheFirstNorTheNumberMatch() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define ROWS (parse-strip-windows PAYLOAD))")
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(5))
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (r) (cdr (assoc 'app r))) ROWS)
                        (list "Dia" "iTerm2" "Telegram" "Signal" "Obsidian"))
                """) == .true)
    }

    /// Rows carry the six fields the listing and the join need, in strip order.
    /// `focused` marks paneru's own focused window (the `.current` row), and an
    /// empty title stays an empty string rather than becoming #f — the block
    /// omits the detail span on "", and would render "#f" on anything else.
    @Test func parseCarriesEveryRowField() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define R (list-ref (parse-strip-windows PAYLOAD) 1))")
        #expect(try engine.evaluate("(cdr (assoc 'window-id R))") == .fixnum(20786))
        #expect(try engine.evaluate("(cdr (assoc 'bundle-id R))") == .string("com.googlecode.iterm2"))
        #expect(try engine.evaluate("(cdr (assoc 'app R))") == .string("iTerm2"))
        #expect(try engine.evaluate("(cdr (assoc 'title R))") == .string("modaliser"))
        #expect(try engine.evaluate("(cdr (assoc 'focused R))") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'floating R))") == .false)
        // The untitled head row keeps "" rather than #f.
        try engine.evaluate("(define R0 (car (parse-strip-windows PAYLOAD)))")
        #expect(try engine.evaluate("(cdr (assoc 'title R0))") == .string(""))
        #expect(try engine.evaluate("(cdr (assoc 'focused R0))") == .false)
    }

    /// A floating window is an ordinary row. It occupies no column, so
    /// `window focus <n>` could never name it — the id join can, which is half
    /// of ADR-0024's case.
    @Test func parseKeepsAFloatingWindowAsAnOrdinaryRow() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define R (list-ref (parse-strip-windows PAYLOAD) 3))")
        #expect(try engine.evaluate("(cdr (assoc 'app R))") == .string("Signal"))
        #expect(try engine.evaluate("(cdr (assoc 'floating R))") == .true)
    }

    /// Malformed, empty and structurally surprising payloads all degrade to no
    /// rows rather than raising. This is the property that matters most in the
    /// whole file: the parse sits on the come-to-rest path, so a raise here is
    /// a leader press that errors instead of opening a screen.
    @Test(arguments: [
        ("empty output — a down daemon, or the inert seam", "\"\""),
        ("not JSON at all", "\"paneru: command not found\""),
        ("truncated JSON", "\"{\\\"virtual_workspaces\\\":[{\\\"act\""),
        ("valid JSON, no workspaces key", "\"{\\\"version\\\":1}\""),
        ("workspaces present but not an array", "\"{\\\"virtual_workspaces\\\":42}\""),
        ("an active workspace with no windows key", "\"{\\\"virtual_workspaces\\\":[{\\\"active\\\":true}]}\""),
        ("an active workspace with an empty strip",
         "\"{\\\"virtual_workspaces\\\":[{\\\"active\\\":true,\\\"windows\\\":[]}]}\""),
        ("no workspace is active",
         "\"{\\\"virtual_workspaces\\\":[{\\\"active\\\":false,\\\"windows\\\":[{\\\"window_id\\\":1}]}]}\""),
    ])
    func parseDegradesToNoRowsRatherThanRaising(_ label: String, _ source: String) throws {
        let engine = try engineWithFixtures()
        #expect(
            try engine.evaluate("(null? (parse-strip-windows \(source)))") == .true,
            "expected no rows for: \(label)")
    }

    /// A window object with no usable `window_id` is dropped. The id is both
    /// the join key and the dispatch state's id, so a row without one could be
    /// neither focused nor addressed — and would collide with any other such
    /// row in the state table.
    @Test func parseDropsARowWithNoNumericWindowId() throws {
        let engine = try engineWithFixtures()
        // One line: LispKit's reader rejects a raw newline inside a string
        // literal, and this JSON has to survive as one.
        let json =
            #"{"virtual_workspaces":[{"active":true,"windows":["#
            + #"{"app_name":"Ghost"},"#
            + #"{"window_id":"7","app_name":"Stringy"},"#
            + #"{"window_id":7,"app_name":"Real"}]}]}"#
        try engine.evaluate("(define ROWS (parse-strip-windows \(Self.literal(json))))")
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'app (car ROWS)))") == .string("Real"))
    }

    // MARK: - The join (test seam 5 — direct call, no seam)

    /// The join recovers `ownerPid` by window id, keeps strip order, and keeps
    /// its length: paneru decides membership and order, Modaliser contributes
    /// only the pid. An enumerated window paneru does not report (55555) is not
    /// a row — the enumeration is a lookup table here, never a second source of
    /// rows.
    @Test func joinRecoversOwnerPidAndPreservesStripOrderAndLength() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define T (join-strip-targets (parse-strip-windows PAYLOAD) ENUM))")
        #expect(try engine.evaluate("(length T)") == .fixnum(5))
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (t) (cdr (assoc 'owner-pid t))) T)
                        (list 501 4471 733 902 #f))
                """) == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (t) (cdr (assoc 'app t))) T)
                        (list "Dia" "iTerm2" "Telegram" "Signal" "Obsidian"))
                """) == .true)
    }

    /// A strip row the enumeration does not carry keeps its place with
    /// `owner-pid` #f. It is listed, it is labelled, and its label dispatches
    /// to nothing — the one new failure mode ADR-0024 accepts, and it must not
    /// raise on the way there.
    @Test func joinLeavesAnUnmatchedRowInPlaceWithNoPid() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define T (list-ref (join-strip-targets (parse-strip-windows PAYLOAD) ENUM) 4))")
        #expect(try engine.evaluate("(cdr (assoc 'app T))") == .string("Obsidian"))
        #expect(try engine.evaluate("(cdr (assoc 'owner-pid T))") == .false)
    }

    /// An empty enumeration — a bare engine, or a genuinely empty space — makes
    /// every row unmatched without losing one. The listing still renders; only
    /// its dispatch is gone.
    @Test func joinWithAnEmptyEnumerationKeepsEveryRowUnfocusable() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("(define T (join-strip-targets (parse-strip-windows PAYLOAD) '()))")
        #expect(try engine.evaluate("(length T)") == .fixnum(5))
        #expect(
            try engine.evaluate("(null? (filter (lambda (t) (cdr (assoc 'owner-pid t))) T))") == .true)
    }

    // MARK: - Focusing (direct call, no seam)

    /// The choice alist `focus-window` reads, pinned by spelling. `ownerPid` is
    /// the key it no-ops without, and `windowId` is what makes the focus land
    /// on *this* window rather than the app's frontmost one — both are read out
    /// of the alist by name in Swift, so a typo here is a silent no-op on a
    /// live desktop and invisible everywhere else.
    ///
    /// This is a pure function precisely so it can be pinned without a third
    /// seam over `focus-window` itself.
    @Test func focusChoiceCarriesTheKeysFocusWindowReadsByName() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (define C (strip-focus-choice
                      (list-ref (join-strip-targets (parse-strip-windows PAYLOAD) ENUM) 2)))
        """)
        #expect(try engine.evaluate("(cdr (assoc 'ownerPid C))") == .fixnum(733))
        #expect(try engine.evaluate("(cdr (assoc 'windowId C))") == .fixnum(23552))
        #expect(try engine.evaluate("(cdr (assoc 'text C))") == .string("Thomas"))
    }

    // MARK: - Lowering an assignment (test seam 6 — direct call, no seam)

    /// The all-single-key case: one edge and one Terminal state per target, in
    /// strip order, each edge pointing at its own target's state id.
    @Test func providerResultLowersSingleKeyLabelsToOneEdgeAndStateEach() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (define TARGETS (join-strip-targets (parse-strip-windows PAYLOAD) ENUM))
          (define R (strip-provider-result
                      (list (cons "h" (list-ref TARGETS 0))
                            (cons "j" (list-ref TARGETS 1)))
                      "global/w" "Strip"))
          (define EDGES (cdr (assoc 'edges R)))
          (define STATES (cdr (assoc 'states R)))
        """)
        #expect(try engine.evaluate("(length EDGES)") == .fixnum(2))
        #expect(try engine.evaluate("(length STATES)") == .fixnum(2))
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES) (list "h" "j"))
                """) == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                        (list "paneru-strip-target/23141" "paneru-strip-target/20786"))
                """) == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (s) (cdr (assoc 'id s))) STATES)
                        (list "paneru-strip-target/23141" "paneru-strip-target/20786"))
                """) == .true)
    }

    /// An unlabelled target (past both pools) and an unmatched one (no pid) are
    /// both dropped from the *edge set* and from nothing else. They still
    /// occupy their place in the assignment, which is what the block renders.
    @Test func providerResultDropsUnlabelledAndUnmatchedTargetsFromTheEdgeSet() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (define TARGETS (join-strip-targets (parse-strip-windows PAYLOAD) ENUM))
          (define R (strip-provider-result
                      (list (cons "h" (list-ref TARGETS 0))
                            (cons #f  (list-ref TARGETS 1))     ; labelless tail
                            (cons "k" (list-ref TARGETS 4)))    ; Obsidian — no pid
                      "global/w" "Strip"))
        """)
        #expect(try engine.evaluate("(length (cdr (assoc 'edges R)))") == .fixnum(1))
        #expect(try engine.evaluate("(length (cdr (assoc 'states R)))") == .fixnum(1))
        #expect(
            try engine.evaluate(
                "(cdr (assoc 'trigger (car (cdr (assoc 'edges R)))))") == .string("h"))
    }

    /// A leader whose every second key was dropped contributes no group at all,
    /// so the leader key stays dead rather than narrowing into an empty
    /// listing. Worth pinning because the alternative — minting the prefix
    /// state first and filtering later — looks equivalent and is not.
    @Test func providerResultMintsNoPrefixStateForALeaderWithNoFocusableTarget() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (define TARGETS (join-strip-targets (parse-strip-windows PAYLOAD) ENUM))
          (define R (strip-provider-result
                      (list (cons "ah" (list-ref TARGETS 4)))   ; Obsidian — no pid
                      "global/w" "Strip"))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
    }

    // MARK: - The provider's gather (test seam 3 — both seams, together)

    /// Bind the whole pipeline behind the two seams and run it as the engine
    /// would at come-to-rest.
    ///
    /// The alphabets are chosen so escalation happens with a *small*,
    /// exhaustively checkable survivor set: three single keys against five
    /// targets forces `jump-labels-assign` to promote leader "a" (which is not
    /// itself a single, so it costs no single slot), giving h/j/k to the first
    /// three and "ah"/"aj" to the last two.
    private func runProvider(
        singles: String = #"(list "h" "j" "k")"#,
        leaders: String = #"(list "a")"#,
        seconds: String = #"(list "h" "j" "k")"#,
        ownerId: String = "global/w"
    ) throws -> SchemeEngine {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (define seen '())
          (current-shell-runner (lambda (cmd) (set! seen (cons cmd seen)) PAYLOAD))
          (define P (strip-provider 'single-alphabet \(singles)
                                    'leader-alphabet \(leaders)
                                    'second-alphabet \(seconds)
                                    'panel-label "Strip"
                                    'enumerate (lambda () ENUM)))
          (define R (P "\(ownerId)"))
          (define EDGES (cdr (assoc 'edges R)))
          (define STATES (cdr (assoc 'states R)))
        """)
        return engine
    }

    /// The gather issues exactly one command — the read-only state query — and
    /// nothing else. It sits on the dispatch path, where a stray extra spawn is
    /// paid on every keypress of a `'next 'self` op.
    @Test func providerQueriesStateOnceAndOnlyThroughTheShellSeam() throws {
        let engine = try runProvider()
        #expect(try engine.evaluate("(length seen)") == .fixnum(1))
        #expect(
            try engine.evaluate("(string-contains? (car seen) \"paneru query state --json\")")
                == .true)
    }

    /// Three single-key edges plus one leader edge; three Terminal states plus
    /// one prefix state. Obsidian's "aj" is unmatched, so leader "a" narrows to
    /// Signal alone.
    @Test func providerLowersTheAssignmentToEdgesAndStates() throws {
        let engine = try runProvider()
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES)
                        (list "h" "j" "k" "a"))
                """) == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                        (list "paneru-strip-target/23141"
                              "paneru-strip-target/20786"
                              "paneru-strip-target/23552"
                              "global/w/a"))
                """) == .true)
        #expect(try engine.evaluate("(length STATES)") == .fixnum(4))
    }

    /// A label focuses the window its row was drawn beside — the join asserted
    /// end to end, through the assignment, in one place. `k` is Telegram's
    /// label, `paneru-strip-target/23552` is Telegram's state, and 733 is the
    /// pid the enumeration held for window 23552; ADR-0024's whole mechanism is
    /// those three lining up.
    @Test func aJumpLabelResolvesToItsOwnWindowsFocusTarget() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define TARGET-ID
            (cdr (assoc 'target
              (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "k")) EDGES))))
          (define TELEGRAM
            (find (lambda (t) (equal? (cdr (assoc 'window-id t)) 23552))
                  (join-strip-targets (parse-strip-windows PAYLOAD) ENUM)))
        """)
        #expect(try engine.evaluate("TARGET-ID") == .string("paneru-strip-target/23552"))
        #expect(
            try engine.evaluate(
                "(find (lambda (s) (equal? (cdr (assoc 'id s)) TARGET-ID)) STATES)")
                != .false)
        #expect(try engine.evaluate("(cdr (assoc 'ownerPid (strip-focus-choice TELEGRAM)))")
                == .fixnum(733))
    }

    /// The narrowing prefix state's three non-negotiable properties, asserted
    /// together because each fails silently on its own:
    ///
    /// - **its id is `<owner-id>/<leader>`** — the convention permanent child
    ///   states use. `strip-id-prefix` derives a breadcrumb segment by
    ///   `substring`-ing the parent's id off the child's, so any other shape
    ///   yields a garbled segment or raises outright;
    /// - **its `'up` edge targets `<owner-id>`** — or backspace does not
    ///   un-narrow and `ancestors-within-tree` stops the climb early;
    /// - **its `'payload` carries the two-layer node shape** `screen` lowers a
    ///   registered root's payload into (a `'children` list holding the block,
    ///   plus a `'display` clause placing it by type). `fsm-resolved-payload`
    ///   hands this alist to the façade as `modal-current-node` and the
    ///   panel-grid renderer resolves both off whatever that is (ADR-0011), so
    ///   the *unchanged* renderer draws the narrowed listing. A payload-less
    ///   prefix state narrows into a blank screen.
    ///
    /// The panel's label is the user's `'panel-label`, threaded through
    /// untouched — no library file may author a label (ADR-0021).
    @Test func prefixStateCarriesItsIdUpEdgeAndTwoLayerPayload() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define PREFIX (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/w/a")) STATES))
          (define PAYLOAD-OF (cdr (assoc 'payload PREFIX)))
          (define CHILDREN (node-children PAYLOAD-OF))
          (define PANEL (car (node-display-ref PAYLOAD-OF 'panels)))
          (define UP (find (lambda (e) (eq? (cdr (assoc 'trigger e)) 'up))
                           (cdr (assoc 'edges PREFIX))))
        """)
        #expect(try engine.evaluate("PREFIX") != .false)
        #expect(try engine.evaluate("(cdr (assoc 'target UP))") == .string("global/w"))
        #expect(try engine.evaluate("(length CHILDREN)") == .fixnum(1))
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (car CHILDREN))) 'paneru-strip)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'label PANEL))") == .string("Strip"))
        #expect(
            try engine.evaluate("(equal? (cdr (assoc 'rows PANEL)) '((block . paneru-strip)))")
                == .true)
    }

    /// The prefix state's second-key edges, and the block it renders, are built
    /// from the same survivor list — so the narrowed legend cannot show a row
    /// the narrowed dispatch does not have. Leader "a" survives with Signal
    /// alone (Obsidian's "aj" was dropped for having no pid).
    @Test func prefixStateSecondKeysAndNarrowedRowsAreTheSameSurvivors() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define PREFIX (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/w/a")) STATES))
          (define SECONDS (filter (lambda (e) (string? (cdr (assoc 'trigger e))))
                                  (cdr (assoc 'edges PREFIX))))
          (define BLOCK (car (node-children (cdr (assoc 'payload PREFIX)))))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn BLOCK))))))
        """)
        #expect(
            try engine.evaluate(
                "(equal? (map (lambda (e) (cdr (assoc 'trigger e))) SECONDS) (list \"h\"))")
                == .true)
        #expect(
            try engine.evaluate(
                "(equal? (map (lambda (e) (cdr (assoc 'target e))) SECONDS)"
                    + " (list \"paneru-strip-target/27020\"))") == .true)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'app (car ROWS)))") == .string("Signal"))
        #expect(try engine.evaluate("(cdr (assoc 'label (car ROWS)))") == .string("h"))
    }

    /// The prefix state carries its **own** `'provider`, re-minting exactly the
    /// Terminal states its second-key edges target. This is a requirement, not
    /// an optimisation: provided states are Visit-scoped, and stepping into the
    /// prefix state *begins a new Visit* whose provided table holds only what
    /// that state's own provider returns — so without this the second key
    /// resolves to a state nobody minted. It re-mints from the survivor pairs,
    /// issuing no second paneru query.
    @Test func prefixStateRemintsItsOwnTerminalStatesWithoutQueryingAgain() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define PREFIX (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/w/a")) STATES))
          (define BEFORE (length seen))
          (define INNER ((cdr (assoc 'provider PREFIX)) "global/w/a"))
          (define INNER-STATES (cdr (assoc 'states INNER)))
        """)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (s) (cdr (assoc 'id s))) INNER-STATES)
                        (list "paneru-strip-target/27020"))
                """) == .true)
        #expect(try engine.evaluate("(= (length seen) BEFORE)") == .true)
    }

    /// The provider is invoked with the id of the state it was lowered onto
    /// (provider-state-id-k9), and that id — whatever it is — is what the
    /// prefix state hangs off. Nesting the screen one level deeper must not
    /// break the breadcrumb, which is exactly what a hardcoded id would do.
    @Test func prefixStateIdFollowsWhateverOwnerIdTheEngineSupplies() throws {
        let engine = try runProvider(ownerId: "global/x/w")
        #expect(
            try engine.evaluate(
                "(if (find (lambda (s) (equal? (cdr (assoc 'id s)) \"global/x/w/a\")) STATES) #t #f)")
                == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (cdr (assoc 'target
                          (find (lambda (e) (eq? (cdr (assoc 'trigger e)) 'up))
                                (cdr (assoc 'edges
                                  (find (lambda (s) (equal? (cdr (assoc 'id s)) "global/x/w/a"))
                                        STATES))))))
                        "global/x/w")
                """) == .true)
    }

    // MARK: - The Strip snapshot

    /// `strip-listing`'s block renders the **exact** assignment the provider
    /// took this Visit — every row, in strip order, labels included, unmatched
    /// and unlabelled alike. The block never queries, so the listing and the
    /// dispatch cannot disagree; that is the whole reason the snapshot exists.
    @Test func theListingBlockRendersTheProvidersSnapshot() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define BEFORE (length seen))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (strip-listing)))))))
        """)
        #expect(try engine.evaluate("(= (length seen) BEFORE)") == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (r) (cdr (assoc 'label r))) ROWS)
                        (list "h" "j" "k" "ah" "aj"))
                """) == .true)
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (r) (cdr (assoc 'app r))) ROWS)
                        (list "Dia" "iTerm2" "Telegram" "Signal" "Obsidian"))
                """) == .true)
        // paneru's focused window is the `.current` row.
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (r) (cdr (assoc 'focused r))) ROWS)
                        (list #f #t #f #f #f))
                """) == .true)
    }

    /// A strip longer than the user's label pools leaves a tail unlabelled: the
    /// rows still render, with a blank key and no dispatch. The listing is a
    /// picture of the strip, and a row that outran the alphabet is still on the
    /// strip.
    @Test func aStripLongerThanTheAlphabetsRendersAnUnlabelledTail() throws {
        let engine = try runProvider(
            singles: #"(list "h")"#, leaders: "'()", seconds: "'()")
        try engine.evaluate("""
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (strip-listing)))))))
        """)
        #expect(try engine.evaluate("(length EDGES)") == .fixnum(1))
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(5))
        #expect(
            try engine.evaluate(
                """
                (equal? (map (lambda (r) (cdr (assoc 'label r))) ROWS)
                        (list "h" "" "" "" ""))
                """) == .true)
    }

    // MARK: - Degradation (spec "Degradation")

    /// A down daemon: the query answers "", the parse yields no rows, and the
    /// provider returns an empty edge set and an empty listing. Quiet and
    /// local, never an error reaching a leader press.
    @Test func aDownDaemonYieldsNoEdgesAndAnEmptyListing() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (current-shell-runner (lambda (cmd) ""))
          (define R ((strip-provider 'single-alphabet (list "h" "j")
                                     'leader-alphabet (list "a")
                                     'second-alphabet (list "h")
                                     'enumerate (lambda () ENUM))
                     "global/w"))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (strip-listing)))))))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
        #expect(try engine.evaluate("(null? ROWS)") == .true)
    }

    /// A bare engine — no shell runner installed, which is every engine
    /// `swift test` builds — reaches nothing and yields nothing. In production
    /// this state cannot arise: `installed?` is false there too, so the
    /// **Paneru-installed composition** takes its non-paneru branch and this
    /// provider is never wired at all (spec "Degradation", row 3).
    @Test func aBareEngineProviderReachesNothing() throws {
        let engine = try engineWithFixtures()
        #expect(try engine.evaluate("(current-shell-runner)") == .false)
        try engine.evaluate("""
          (define R ((strip-provider 'single-alphabet (list "h")
                                     'enumerate (lambda () ENUM))
                     "global/w"))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges R)))") == .true)
    }

    /// With no alphabets at all, nothing is labelled and nothing dispatches —
    /// the library ships no default alphabet, not even a fallback one, because
    /// jump labels are keys and no library file may author a key (ADR-0021).
    /// The rows still render.
    @Test func withNoAlphabetsNothingIsLabelledAndTheLibraryInventsNone() throws {
        let engine = try engineWithFixtures()
        try engine.evaluate("""
          (current-shell-runner (lambda (cmd) PAYLOAD))
          (define R ((strip-provider 'enumerate (lambda () ENUM)) "global/w"))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (strip-listing)))))))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges R)))") == .true)
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(5))
        #expect(
            try engine.evaluate("(null? (filter (lambda (r) (not (equal? (cdr (assoc 'label r)) \"\"))) ROWS))")
                == .true)
    }
}
