import Testing

@testable import Modaliser

/// Tests for the **project panel** half of `(modaliser apps vscode)`
/// (vscode-project-panel-k4) — the Edge provider that labels every open
/// project at come-to-rest, and the listing block that draws the assignment
/// it took.
///
/// The suite's siblings are `ModaliserAppsVscodeLibraryTests` (the window and
/// workspace surfaces) and `ModaliserJumpListLibraryTests`, which pins the
/// lowering machinery this composes. What is asserted *here* is the
/// composition: that VSCode's rows, VSCode's ids and VSCode's focus action
/// line up with each other.
///
/// **One seam, and nothing else reaches outward.** `project-provider`'s
/// `'enumerate` option answers the window enumeration with a canned list. It
/// is a *determinism* seam as much as an isolation one: `list-windows`
/// performs an accessibility sweep of every running application, so a
/// provider test that let it run would assert an edge set determined by
/// whatever the developer happened to have open — vacuous on a quiet machine
/// and flaky on a busy one, and dependent on whether VSCode itself was
/// running. The seam is bypassed nowhere below, so `focus-window` is never
/// called and no editor is contacted.
@Suite("(modaliser apps vscode) project panel")
struct ModaliserAppsVscodeProjectPanelTests {

    // MARK: - Fixtures

    /// A canned window enumeration in `list-windows`' own shape.
    ///
    /// Five entries carrying four cases at once:
    ///
    /// - **Four VSCode windows**, whose titles are shaped exactly as VSCode
    ///   writes them under the default profile — `<file> — <folder>`, and a
    ///   bare `<folder>` when no editor is open. The folder names are long on
    ///   purpose: the human runs one worktree per window and they routinely
    ///   run past forty characters, which is the case the listing block was
    ///   split from `paneru-strip` to render.
    /// - **Deliberately not in alphabetical order**, so a provider that took
    ///   the enumeration's order — which is front-to-back stacking order, and
    ///   therefore changes every time a window is focused — is red here.
    /// - **A Zed window**, which must be filtered out entirely: the panel
    ///   lists VSCode's windows, and `'icon` is the only field that says so.
    /// - **A VSCode window with no `ownerPid`** (`zed-fork`), the inert case:
    ///   `focus-window` no-ops without a pid, so the row earns a label and a
    ///   listing row but no edge.
    private static let enumeration = """
      (list (list (cons 'text "vscode.sld — Modaliser.local-tree-for-vscode")
                  (cons 'icon "com.microsoft.VSCode") (cons 'windowId 101) (cons 'ownerPid 11))
            (list (cons 'text "README.md — quint-llm-kit")
                  (cons 'icon "com.microsoft.VSCode") (cons 'windowId 103) (cons 'ownerPid 13))
            (list (cons 'text "config.scm — dotfiles")
                  (cons 'icon "dev.zed.Zed")          (cons 'windowId 900) (cons 'ownerPid 99))
            (list (cons 'text "grove.add-user-guide-and-code-walkthroughs-for-all-crates")
                  (cons 'icon "com.microsoft.VSCode") (cons 'windowId 102) (cons 'ownerPid 12))
            (list (cons 'text "main.rs — zed-fork")
                  (cons 'icon "com.microsoft.VSCode") (cons 'windowId 104) (cons 'ownerPid #f)))
      """

    /// An engine with the library imported and the enumeration bound. No shell
    /// runner is installed — nothing here spawns, and its absence proves it.
    private func engine() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps vscode) (modaliser fsm) (modaliser util))")
        try engine.evaluate("(define ENUM \(Self.enumeration))")
        return engine
    }

    /// Runs the provider once against the fixture with five single-key
    /// candidates — one more than there are projects, so nothing escalates and
    /// the assertions below are about ordering and dropping rather than about
    /// leaders (which `ModaliserJumpListLibraryTests` covers in the machinery).
    ///
    /// The alphabets are the *test's* to choose, exactly as they are the
    /// user's at runtime: the library defaults none (ADR-0021).
    private func runProvider(_ owner: String = "com.microsoft.VSCode") throws -> SchemeEngine {
        let engine = try self.engine()
        try engine.evaluate("""
          (define P (project-provider 'single-alphabet '("a" "s" "d" "f" "g")
                                      'leader-alphabet '("q" "w")
                                      'second-alphabet '("a" "s" "d" "f" "g")
                                      'panel-label     "Projects"
                                      'enumerate       (lambda () ENUM)))
          (define R (P "\(owner)"))
          (define EDGES  (cdr (assoc 'edges  R)))
          (define STATES (cdr (assoc 'states R)))
        """)
        return engine
    }

    // MARK: - Surface

    /// Both panel exports bind. Each is public contract the moment a config
    /// can reference it.
    @Test func exportsThePanelSurface() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps vscode))")
        for name in ["project-provider", "project-listing"] {
            #expect(
                try engine.evaluate("(procedure? \(name))") == .true,
                "expected \(name) to be exported")
        }
    }

    // MARK: - The assignment

    /// Labels land on projects in ALPHABETICAL order, not the enumeration's.
    /// The enumeration's order is front-to-back stacking order and reshuffles
    /// every time a window is focused; a panel whose labels move between
    /// presses cannot be learned, and learning them is the whole reason this
    /// exists rather than the chooser it replaced.
    @Test func labelsFollowProjectOrderNotStackingOrder() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing)))))))
        """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (r) (cdr (assoc 'label r))) ROWS)
                      (list "a" "s" "d" "f"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (r) (cdr (assoc 'name r))) ROWS)
                      (list "grove.add-user-guide-and-code-walkthroughs-for-all-crates"
                            "Modaliser.local-tree-for-vscode"
                            "quint-llm-kit"
                            "zed-fork"))
            """) == .true)
    }

    /// A label reaches the window its row was drawn beside. The edge's target
    /// is that project's Terminal state id, the id is built from that window's
    /// own id, and a state with it exists — the three lining up is what makes
    /// a keypress focus the right project.
    @Test func eachLabelResolvesToItsOwnWindowsTerminalState() throws {
        let engine = try runProvider()
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) EDGES) (list "a" "s" "d"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'target e))) EDGES)
                      (list "vscode-project-target/102"
                            "vscode-project-target/101"
                            "vscode-project-target/103"))
            """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (s) (cdr (assoc 'id s))) STATES)
                      (list "vscode-project-target/102"
                            "vscode-project-target/101"
                            "vscode-project-target/103"))
            """) == .true)
        // Terminal: no edges of its own, so a jump exits the modal.
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges (car STATES))))") == .true)
    }

    /// Only VSCode's own windows are listed. `'icon` carries the bundle id and
    /// is the only field that distinguishes them — the Zed window in the
    /// fixture has a plausible project-shaped title and must still be absent.
    @Test func windowsOfOtherAppsAreNotListed() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define NAMES (map (lambda (r) (cdr (assoc 'name r)))
                             (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing))))))))
        """)
        #expect(try engine.evaluate("(length NAMES)") == .fixnum(4))
        #expect(try engine.evaluate("(if (member \"dotfiles\" NAMES) #t #f)") == .false)
    }

    /// A window the enumeration gave no `ownerPid` still gets its label and
    /// its listing row, and gets no edge. `focus-window` no-ops without a pid,
    /// so an edge would be a key that silently does nothing; dropping the row
    /// during ASSIGNMENT instead would renumber every label below it on one
    /// transient enumeration miss, and the labels are muscle memory. The cost
    /// is one dead key, and it is the cheaper of the two.
    @Test func aWindowWithNoPidKeepsItsLabelAndRowButEarnsNoEdge() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing)))))))
          (define ZED (list-ref ROWS 3))
        """)
        #expect(try engine.evaluate("(cdr (assoc 'name  ZED))") == .string("zed-fork"))
        #expect(try engine.evaluate("(cdr (assoc 'label ZED))") == .string("f"))
        #expect(
            try engine.evaluate("""
              (if (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "f")) EDGES) #t #f)
            """) == .false)
        #expect(try engine.evaluate("(length EDGES)") == .fixnum(3))
    }

    /// The prefix state a leader narrows into hangs off whatever owner id the
    /// engine supplied, never a literal baked into the library — the panel is
    /// composed under a scope symbol the *user* spells, so the id cannot be
    /// known here.
    @Test func prefixStatesFollowTheOwnerIdTheEngineSupplies() throws {
        let engine = try self.engine()
        // One single-key candidate against four projects forces escalation.
        try engine.evaluate("""
          (define P (project-provider 'single-alphabet '("a")
                                      'leader-alphabet '("q" "w")
                                      'second-alphabet '("a" "s")
                                      'panel-label     "Projects"
                                      'enumerate       (lambda () ENUM)))
          (define R (P "global/somewhere/else"))
          (define IDS (map (lambda (s) (cdr (assoc 'id s))) (cdr (assoc 'states R))))
        """)
        #expect(
            try engine.evaluate("""
              (if (member "global/somewhere/else/q" IDS) #t #f)
            """) == .true)
    }

    /// With no alphabets the library invents none: every row is unlabelled and
    /// no edge is minted. Jump labels are keys, and no file under
    /// `lib/modaliser` may author one (ADR-0021) — an omitted alphabet is an
    /// empty panel, never a library-chosen default.
    @Test func withNoAlphabetsNothingIsLabelledAndTheLibraryInventsNone() throws {
        let engine = try self.engine()
        try engine.evaluate("""
          (define R ((project-provider 'enumerate (lambda () ENUM)) "com.microsoft.VSCode"))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing)))))))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges  R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
        // The rows are still there — the listing is a picture of what is open.
        #expect(try engine.evaluate("(length ROWS)") == .fixnum(4))
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (r) (cdr (assoc 'label r))) ROWS) (list "" "" "" ""))
            """) == .true)
    }

    /// An empty enumeration yields an empty panel rather than raising. The
    /// provider runs on the come-to-rest path, so a raise here is a leader
    /// press that errors instead of opening a screen — and "no VSCode windows"
    /// is reachable in the ordinary way, by closing them.
    @Test func noVscodeWindowsYieldsAnEmptyPanelNotAnError() throws {
        let engine = try self.engine()
        try engine.evaluate("""
          (define R ((project-provider 'single-alphabet '("a" "s")
                                       'enumerate (lambda () '()))
                     "com.microsoft.VSCode"))
          (define ROWS (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing)))))))
        """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges  R)))") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'states R)))") == .true)
        #expect(try engine.evaluate("(null? ROWS)") == .true)
    }

    /// The listing renders the assignment the provider took THIS Visit, read
    /// from the snapshot rather than re-queried — so the rows a user sees are
    /// the exact assignment their keypress dispatches through, and a label
    /// pressed faster than the overlay appears still works. Running the
    /// provider again over a changed enumeration moves the listing with it.
    @Test func theListingRendersTheProvidersOwnSnapshot() throws {
        let engine = try runProvider()
        try engine.evaluate("""
          (define BEFORE (length (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing))))))))
          ((project-provider 'single-alphabet '("a")
                             'enumerate (lambda ()
                               (list (list (cons 'text "one.rs — solo")
                                           (cons 'icon "com.microsoft.VSCode")
                                           (cons 'windowId 7) (cons 'ownerPid 7)))))
           "com.microsoft.VSCode")
          (define AFTER (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (project-listing)))))))
        """)
        #expect(try engine.evaluate("BEFORE") == .fixnum(4))
        #expect(try engine.evaluate("(length AFTER)") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'name (car AFTER)))") == .string("solo"))
    }
}
