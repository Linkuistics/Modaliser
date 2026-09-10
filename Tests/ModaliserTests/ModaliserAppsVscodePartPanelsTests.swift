import Foundation
import Testing

@testable import Modaliser

/// Tests for the Terminal and Editor panels in `(modaliser apps vscode)`
/// (vscode-part-panels-k7, docs/specs/vscode-window-parts.md decisions 4, 5
/// and 6) — the two pure joins, the two actions, and the two providers.
///
/// **Nothing here reaches a socket.** Every behavioural test lands on
/// `terminal-rows` / `editor-rows`, which are functions from a parsed `parts`
/// reply to targets; the fixture is a reply captured off a real peer. Where a
/// test needs the impure half, it installs a canned runner on
/// `current-vscode-query-runner` or a recording one on
/// `current-vscode-notify-runner`, exactly as the transport suite does. The
/// pointer path defaults to `#f` and no test runs `root.scm`, so there is no
/// path by which this suite could dial a live editor (ADR-0023).
///
/// **The fixture carries the awkward rows on purpose.** Written with happy
/// rows only, an implementation that ignored every rule in decision 1 would
/// pass everything here. So it holds: a terminal with no `cwd`, an editor tab
/// with `token: null` (the inert kind), tabs in two different groups, and a
/// path that does not lie under the workspace. The `focused: false` and
/// `workspace: null` cases get fixtures of their own — the first is the one
/// most likely to be left out, because it is the only one whose correct
/// handling is to produce nothing.
///
/// **What no seam here can reach.** Every assertion below is about the *call*
/// — which bytes went to which peer, which target a label was lowered onto —
/// and none is about the *effect*, because the effect is VSCode's. The
/// per-kind activation table lives in the extension and is tested in its own
/// project; the two cases a fake passes and a real window fails (one file open
/// in two editor groups after a reorder, and an already-active preview tab)
/// are driven by hand and are in this leaf's `Done when`.
@Suite("(modaliser apps vscode) part panels")
struct ModaliserAppsVscodePartPanelsTests {

    /// A reply in the extension's own shape. `/Users/someone/Project` is the
    /// workspace; `/etc/hosts` deliberately is not under it.
    private static let partsReply = """
      {"id":"modaliser",
       "result":{"protocol":1,
                 "focused":true,
                 "peer":"/Users/someone/.config/modaliser/vscode/vs-abc.sock",
                 "workspace":"/Users/someone/Project",
                 "terminals":[{"token":1,"name":"zsh","cwd":"/Users/someone/Project/lib","active":true},
                              {"token":2,"name":"build","cwd":null,"active":false}],
                 "editors":[{"token":3,"label":"fsm.sld","path":"/Users/someone/Project/lib/fsm.sld",
                             "active":true,"dirty":false,"group":1},
                            {"token":4,"label":"hosts","path":"/etc/hosts",
                             "active":false,"dirty":true,"group":2},
                            {"token":null,"label":"Release Notes","path":null,
                             "active":false,"dirty":false,"group":2}]}}
      """

    /// The same window with no folder open: `workspace` is JSON null. Not an
    /// empty-listing case — an ordinary listing whose paths come out
    /// unshortened (decision 3).
    private static let folderlessReply = """
      {"id":"modaliser",
       "result":{"protocol":1,
                 "focused":true,
                 "peer":"/Users/someone/.config/modaliser/vscode/vs-def.sock",
                 "workspace":null,
                 "terminals":[{"token":1,"name":"zsh","cwd":"/Users/someone","active":false}],
                 "editors":[{"token":2,"label":"notes.md","path":"/Users/someone/notes.md",
                             "active":true,"dirty":false,"group":1}]}}
      """

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (prefix (modaliser apps vscode) code:)
                  (only (modaliser json) json-parse json-ref)
                  (only (modaliser util) alist-ref)
                  (modaliser blocks part-list))
          """)
        return engine
    }

    /// Binds `PARTS` to the parsed result of REPLY, through the library's own
    /// `vscode-parts` and therefore through its `focused` and `protocol`
    /// gates — not by parsing the fixture directly, which would test the
    /// fixture rather than the library.
    private func bindParts(_ engine: SchemeEngine, _ reply: String) throws {
        let peer = "/Users/someone/.config/modaliser/vscode/vs-abc.sock"
        let pointer = try pointerFile(naming: peer)
        try engine.evaluate("""
          (code:current-vscode-socket-pointer-path \(schemeString(pointer)))
          (code:current-vscode-query-runner
            (lambda (peer method params) (json-parse \(schemeString(reply)))))
          (define PARTS (code:vscode-parts))
          """)
    }

    private func pointerFile(naming peer: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-vscode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let pointer = directory.appendingPathComponent("focused")
        try "\(peer)\n".write(to: pointer, atomically: true, encoding: .utf8)
        return pointer.path
    }

    private func schemeString(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    // MARK: - The surface

    @Test func exportsResolveAsProcedures() throws {
        let engine = try loaded()
        for name in [
            "code:terminal-rows", "code:editor-rows", "code:shorten-path",
            "code:terminal-source", "code:editor-source",
            "code:focus-terminal!", "code:focus-editor-tab!",
            "code:terminal-provider", "code:terminal-listing",
            "code:editor-provider", "code:editor-listing",
        ] {
            #expect(try engine.evaluate("(procedure? \(name))") == .true, "\(name)")
        }
    }

    // MARK: - The joins

    @Test func terminalRowsListEveryTerminalInReplyOrder() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("(define T (code:terminal-rows PARTS))")
        #expect(try engine.evaluate("(= 2 (length T))") == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (t) (alist-ref t 'text)) T) (list "zsh" "build"))
              """) == .true)
    }

    @Test func editorRowsListEveryTabAcrossEveryGroup() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("(define E (code:editor-rows PARTS))")
        // Three tabs across two groups, in the reply's order — the group
        // boundary is not a break in the listing, only a field on the row.
        #expect(try engine.evaluate("(= 3 (length E))") == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (alist-ref e 'group)) E) (list 1 2 2))
              """) == .true)
    }

    /// **Every target carries the peer the reply itself named.** This is the
    /// half of decision 4 that a token cannot supply: the counter is
    /// per-window, so the integer 3 is live in as many windows as are open,
    /// and a target carrying only the integer would be an address several
    /// windows answer to.
    @Test func everyTargetCarriesTheReplysOwnPeer() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        #expect(
            try engine.evaluate("""
              (let ((all (append (code:terminal-rows PARTS) (code:editor-rows PARTS))))
                (and (= 5 (length all))
                     (null? (filter (lambda (t)
                                      (not (equal? (alist-ref t 'peer)
                                                   (json-ref PARTS "peer"))))
                                    all))))
              """) == .true)
    }

    /// A tab of a kind with no specified activation arrives with `token: null`
    /// and is **listed**, marked inert. Omitting it would make the panel
    /// disagree with the tab strip the human is looking at, and would renumber
    /// every label below it.
    @Test func aTabWithNoTokenIsListedAndMarkedInert() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("(define E (code:editor-rows PARTS))")
        #expect(
            try engine.evaluate("(equal? (alist-ref (caddr E) 'text) \"Release Notes\")") == .true)
        #expect(try engine.evaluate("(alist-ref (caddr E) 'inert)") == .true)
        #expect(try engine.evaluate("(alist-ref (caddr E) 'token)") == .false)
        // And the rows that do have tokens are not inert.
        #expect(try engine.evaluate("(alist-ref (car E) 'inert)") == .false)
    }

    /// An inert row earns no edge and no state, and **renumbers nothing**:
    /// the rows above and below keep the labels they would have had.
    @Test func anInertRowConsumesItsLabelAndGetsNoEdge() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define P (code:editor-provider
                      'single-alphabet '("h" "j" "k")
                      'leader-alphabet '("h" "j" "k")
                      'second-alphabet '("h" "j" "k")
                      'panel-label     "Editors"
                      'enumerate       (lambda () PARTS)))
          (define R (P "global/vscode"))
          """)
        // Three rows, three labels assigned — and only two edges, because the
        // third row has no action behind it.
        #expect(try engine.evaluate("(= 2 (length (cdr (assoc 'edges R))))") == .true)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (e) (cdr (assoc 'trigger e))) (cdr (assoc 'edges R)))
                      (list "h" "j"))
              """) == .true)
        // The listing still draws all three, the third with its label.
        try engine.evaluate("""
          (define ROWS ((cdr (assoc 'on-render-fn (code:editor-listing)))))
          """)
        #expect(
            try engine.evaluate("""
              (equal? (map (lambda (r) (alist-ref r 'label)) (cdr (assoc 'rows ROWS)))
                      (list "h" "j" "k"))
              """) == .true)
        #expect(
            try engine.evaluate("""
              (alist-ref (caddr (cdr (assoc 'rows ROWS))) 'inert)
              """) == .true)
    }

    // MARK: - Path shortening

    /// The workspace prefix comes off, because every row in a one-window
    /// listing shares it and it is the least informative part of a
    /// forty-character path.
    @Test func aPathUnderTheWorkspaceIsShortened() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (car (code:editor-rows PARTS)) 'detail) "lib/fsm.sld")
              """) == .true)
        // A terminal's cwd takes the same rule.
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (car (code:terminal-rows PARTS)) 'detail) "lib")
              """) == .true)
    }

    /// A file opened from outside the workspace keeps its absolute path. The
    /// rule is *shorten where the prefix matches*, never *assume it matches*.
    @Test func aPathOutsideTheWorkspaceIsLeftWhole() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (cadr (code:editor-rows PARTS)) 'detail) "/etc/hosts")
              """) == .true)
    }

    /// **A folderless window is an ordinary listing**, not an empty one: it
    /// lists its parts with `workspace: null` and its paths unshortened
    /// (decision 3). An empty listing here would have been a silent narrowing
    /// of the requirement rather than a degradation.
    @Test func aFolderlessWindowListsNormallyWithUnshortenedPaths() throws {
        let engine = try loaded()
        try bindParts(engine, Self.folderlessReply)
        #expect(try engine.evaluate("(= 1 (length (code:terminal-rows PARTS)))") == .true)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (car (code:editor-rows PARTS)) 'detail)
                      "/Users/someone/notes.md")
              """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (car (code:terminal-rows PARTS)) 'detail) "/Users/someone")
              """) == .true)
    }

    /// A row whose path or cwd is JSON null gets an empty detail rather than
    /// the word "null" or a crash. Two distinct optionals reach here as one
    /// null: a terminal without shell integration, and one whose integration
    /// has reported no cwd.
    @Test func aMissingPathBecomesAnEmptyDetail() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (cadr (code:terminal-rows PARTS)) 'detail) "")
              """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (alist-ref (caddr (code:editor-rows PARTS)) 'detail) "")
              """) == .true)
    }

    /// The separator is required as well as the prefix. Without it a sibling
    /// directory sharing a name prefix would have its leading characters
    /// sliced off and the row would name a file that does not exist — which is
    /// the ordinary case in this very repository, where `Modaliser` and
    /// `Modaliser.local-tree-for-vscode` sit side by side.
    @Test func aSiblingSharingANamePrefixIsNotShortened() throws {
        let engine = try loaded()
        #expect(
            try engine.evaluate("""
              (equal? (code:shorten-path "/w/Modaliser.local-tree/a.txt" "/w/Modaliser")
                      "/w/Modaliser.local-tree/a.txt")
              """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (code:shorten-path "/w/Modaliser/a.txt" "/w/Modaliser") "a.txt")
              """) == .true)
        // A workspace already ending in a separator must not eat a character.
        #expect(
            try engine.evaluate("""
              (equal? (code:shorten-path "/w/M/a.txt" "/w/M/") "a.txt")
              """) == .true)
    }

    // MARK: - The actions

    /// **The notification goes to the target's own peer and no other.**
    /// Without this assertion the whole of decision 4 is an assertion again —
    /// the one thing this design has already been caught at once.
    @Test func anActionIsAddressedToTheTargetsOwnPeer() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define sent '())
          (code:current-vscode-notify-runner
            (lambda (peer method params) (set! sent (cons (list peer method params) sent)) #t))
          ;; The pointer now names a DIFFERENT peer, as it would after the
          ;; human moved to another window between the read and the press.
          (code:current-vscode-socket-pointer-path "/tmp/somewhere-else.sock")
          (code:focus-terminal! (car (code:terminal-rows PARTS)))
          (code:focus-editor-tab! (car (code:editor-rows PARTS)))
          """)
        #expect(try engine.evaluate("(= 2 (length sent))") == .true)
        #expect(
            try engine.evaluate("""
              (null? (filter (lambda (s)
                               (not (equal? (car s) (json-ref PARTS "peer"))))
                             sent))
              """) == .true)
    }

    @Test func eachActionSendsItsOwnMethodAndTheRowsToken() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define sent '())
          (code:current-vscode-notify-runner
            (lambda (peer method params) (set! sent (list method params)) #t))
          (code:focus-terminal! (car (code:terminal-rows PARTS)))
          """)
        #expect(try engine.evaluate("(equal? (car sent) \"focus-terminal\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc \"token\" (cadr sent))) 1)") == .true)
        try engine.evaluate("(code:focus-editor-tab! (cadr (code:editor-rows PARTS)))")
        #expect(try engine.evaluate("(equal? (car sent) \"focus-editor\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc \"token\" (cadr sent))) 4)") == .true)
    }

    // MARK: - Degradation

    /// **A reply from a window that is not focused is discarded whole**, and
    /// the panels are empty rather than showing a neighbouring project's
    /// parts. This is the fixture most likely to be left out, because it is
    /// the only one whose correct handling is to produce nothing.
    @Test func anUnfocusedReplyProducesNoRowsInEitherPanel() throws {
        let engine = try loaded()
        try bindParts(
            engine,
            Self.partsReply.replacingOccurrences(
                of: "\"focused\":true", with: "\"focused\":false"))
        #expect(try engine.evaluate("(null? (code:terminal-source))") == .true)
        #expect(try engine.evaluate("(null? (code:editor-source))") == .true)
    }

    /// An unreachable peer is `#f` all the way to the joins, and `#f` joins to
    /// no rows rather than raising. The provider runs on the come-to-rest
    /// path, so a raise here would be a leader press that errors instead of
    /// opening a screen.
    @Test func anUnreachablePeerProducesNoRowsAndDoesNotRaise() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(null? (code:terminal-rows #f))") == .true)
        #expect(try engine.evaluate("(null? (code:editor-rows #f))") == .true)
        #expect(try engine.evaluate("(null? (code:terminal-source))") == .true)
        #expect(try engine.evaluate("(null? (code:editor-source))") == .true)
    }

    // MARK: - The providers

    /// **The two panels use disjoint state-id namespaces**, so their provided
    /// states cannot shadow each other in the visit's table — where a
    /// collision would be silently last-wins.
    @Test func theTwoPanelsMintStateIdsInDisjointNamespaces() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define (ids provider)
            (map (lambda (s) (cdr (assoc 'id s)))
                 (cdr (assoc 'states
                             ((apply provider (list 'single-alphabet '("q" "w" "e")
                                                    'leader-alphabet '("q")
                                                    'second-alphabet '("q" "w")
                                                    'panel-label "P"
                                                    'enumerate (lambda () PARTS)))
                              "global/vscode")))))
          (define TIDS (ids code:terminal-provider))
          (define EIDS (ids code:editor-provider))
          (define (all-start-with? ids prefix)
            (let ((n (string-length prefix)))
              (null? (filter (lambda (i)
                               (not (and (>= (string-length i) n)
                                         (string=? prefix (substring i 0 n)))))
                             ids))))
          """)
        #expect(try engine.evaluate("(pair? TIDS)") == .true)
        #expect(try engine.evaluate("(pair? EIDS)") == .true)
        #expect(
            try engine.evaluate("""
              (all-start-with? TIDS "vscode-terminal-target/")
              """) == .true)
        #expect(
            try engine.evaluate("""
              (all-start-with? EIDS "vscode-editor-target/")
              """) == .true)
        // And the two sets share nothing at all.
        #expect(
            try engine.evaluate("(null? (filter (lambda (i) (member i EIDS)) TIDS))") == .true)
    }

    /// The listing draws the assignment its own provider took this Visit —
    /// never a re-query, which here would mean a third socket round-trip
    /// against a window that may have changed under it.
    @Test func eachListingDrawsItsOwnProvidersSnapshot() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define TP (code:terminal-provider
                       'single-alphabet '("t" "y") 'leader-alphabet '("t")
                       'second-alphabet '("t" "y") 'panel-label "Terminals"
                       'enumerate (lambda () PARTS)))
          (define EP (code:editor-provider
                       'single-alphabet '("h" "j" "k") 'leader-alphabet '("h")
                       'second-alphabet '("h" "j") 'panel-label "Editors"
                       'enumerate (lambda () PARTS)))
          (TP "global/vscode")
          (EP "global/vscode")
          (define (names block)
            (map (lambda (r) (cdr (assoc 'name r)))
                 (cdr (assoc 'rows ((cdr (assoc 'on-render-fn block)))))))
          """)
        #expect(
            try engine.evaluate("""
              (equal? (names (code:terminal-listing)) (list "zsh" "build"))
              """) == .true)
        #expect(
            try engine.evaluate("""
              (equal? (names (code:editor-listing))
                      (list "fsm.sld" "hosts" "Release Notes"))
              """) == .true)
    }

    /// **The two listings are distinguishable blocks.** Both are `part-list`
    /// blocks — one presentation with two callers — so each carries an
    /// explicit `'id`, which is what `block-ref-id` resolves a panel's
    /// reference by. Without them a screen with both panels is ambiguous and
    /// `resolve-display` raises.
    @Test func theTwoListingsCarryDistinctBlockIds() throws {
        let engine = try loaded()
        #expect(
            try engine.evaluate("""
              (equal? (cdr (assoc 'type (code:terminal-listing)))
                      (cdr (assoc 'type (code:editor-listing))))
              """) == .true)
        #expect(
            try engine.evaluate("""
              (not (equal? (cdr (assoc 'id (code:terminal-listing)))
                           (cdr (assoc 'id (code:editor-listing)))))
              """) == .true)
    }

    /// **No alphabet is defaulted** (ADR-0021). A provider given no alphabets
    /// assigns no labels and therefore mints no edges — it does not fall back
    /// to a library-chosen pool.
    @Test func aProviderWithNoAlphabetsMintsNoEdges() throws {
        let engine = try loaded()
        try bindParts(engine, Self.partsReply)
        try engine.evaluate("""
          (define R ((code:editor-provider 'enumerate (lambda () PARTS)) "global/vscode"))
          """)
        #expect(try engine.evaluate("(null? (cdr (assoc 'edges R)))") == .true)
        // The rows are still there — the listing is a picture of what is open,
        // and a tail past the pools renders with a blank keycap.
        #expect(
            try engine.evaluate("""
              (= 3 (length (cdr (assoc 'rows ((cdr (assoc 'on-render-fn (code:editor-listing))))))))
              """) == .true)
    }

    /// **The shipped example screen's three pools survive leader
    /// promotion.** This is the check no config-load test can make: a panel's
    /// edges are one per surviving single-key label *plus one per promoted
    /// leader*, and promotion is data-dependent — it happens only once a panel
    /// has more rows than its single alphabet covers. So the pool the panels
    /// must keep disjoint from each other and from the screen's own keys is
    /// `single ∪ leader`, and two pools can coexist for months before the
    /// first window with six terminals in it collides.
    ///
    /// The alphabets and static edges here are copied from
    /// `Scheme/examples/vscode.scm`. If that file's keys move, this goes red,
    /// which is the point: `ConfigDslTests.exampleConfigsLoadWithoutErrors`
    /// proves the example *loads*, and a provider does not run until
    /// come-to-rest.
    @Test func theShippedExamplesThreePoolsComposeWithLeadersPromoted() throws {
        let engine = try loaded()
        // Eight parts per panel — past every five-key single alphabet, so
        // every panel promotes leaders and contributes leader edges too.
        let terminals = (1...8).map {
            #"{"token":\#($0),"name":"t\#($0)","cwd":null,"active":false}"#
        }.joined(separator: ",")
        let editors = (9...16).map {
            #"{"token":\#($0),"label":"e\#($0)","path":null,"active":false,"dirty":false,"group":1}"#
        }.joined(separator: ",")
        let crowded = #"""
          {"id":"m","result":{"protocol":1,"focused":true,
           "peer":"/tmp/p.sock","workspace":"/w",
           "terminals":[\#(terminals)],
           "editors":[\#(editors)]}}
          """#
        try bindParts(engine, crowded)
        try engine.evaluate("""
          (import (only (modaliser jump-list) jump-list-validate-composition)
                  (only (modaliser fsm) edge))
          (define project-keys  '("a" "s" "d" "f" "g"))
          (define terminal-keys '("t" "y" "u" "i" "o"))
          (define editor-keys   '("h" "j" "k" "l" ";"))
          (define (pool provider keys)
            ((apply provider (list 'single-alphabet keys 'leader-alphabet keys
                                   'second-alphabet keys 'panel-label "P"
                                   'enumerate (lambda () PARTS)))
             "global/vscode"))
          ;; The example screen's own static edges, verbatim.
          (define screen-edges
            (map (lambda (k) (edge k (string-append "global/vscode/" k)))
                 '("e" "p" "P" "/" "L" "[" "]")))
          """)
        // Both new panels really did promote a leader — otherwise this test
        // would pass without exercising the thing it is named for. A promoted
        // leader is visible as a narrowing PREFIX state, whose id is the
        // owner's id plus the leader key.
        try engine.evaluate("""
          (define (promoted? result)
            (pair? (filter (lambda (s)
                             (let ((i (cdr (assoc 'id s))))
                               (and (>= (string-length i) 14)
                                    (string=? "global/vscode/" (substring i 0 14)))))
                           (cdr (assoc 'states result)))))
          """)
        #expect(
            try engine.evaluate("(promoted? (pool code:terminal-provider terminal-keys))")
                == .true)
        #expect(
            try engine.evaluate("(promoted? (pool code:editor-provider editor-keys))") == .true)
        // And the three compose cleanly against each other and the screen.
        #expect(
            try engine.evaluate("""
              (pair? (jump-list-validate-composition
                       (list (pool code:terminal-provider terminal-keys)
                             (pool code:editor-provider editor-keys))
                       '("Terminals" "Editors")
                       screen-edges '()))
              """) == .true)
        // A control: the same composition with a pool moved onto a screen key
        // must fail, or the assertion above proves nothing.
        #expect(
            raiseMessage(
                engine,
                """
                (jump-list-validate-composition
                  (list (pool code:terminal-provider '("p" "y" "u" "i" "o"))
                        (pool code:editor-provider editor-keys))
                  '("Terminals" "Editors") screen-edges '())
                """) != nil)
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

    // MARK: - The block

    /// `part-list-rows` is a pure assignment → row payload, and it preserves
    /// order and length unconditionally: the rows *are* the listing, so
    /// dropping one would misrepresent it.
    @Test func partListRowsPreservesOrderAndLength() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define A (list (cons "h" (list (cons 'text "a.txt") (cons 'detail "src")))
                          (cons #f  (list (cons 'text "b.txt") (cons 'dirty #t)))
                          (cons "k" (list (cons 'text "c.txt") (cons 'inert #t)))))
          (define R (part-list-rows A))
          """)
        #expect(try engine.evaluate("(= 3 (length R))") == .true)
        // An unlabelled tail row renders with an empty keycap rather than
        // vanishing or collapsing its column.
        #expect(try engine.evaluate("(equal? (alist-ref (cadr R) 'label) \"\")") == .true)
        #expect(try engine.evaluate("(alist-ref (cadr R) 'dirty)") == .true)
        #expect(try engine.evaluate("(alist-ref (caddr R) 'inert)") == .true)
        #expect(try engine.evaluate("(equal? (alist-ref (car R) 'detail) \"src\")") == .true)
    }

    /// A block asked for no id must not carry the key at all: `block-ref-id`
    /// prefers `'id` over `'type`, so a block carrying `(id . #f)` would
    /// answer to nothing and its panel reference would resolve to no child.
    @Test func aBlockWithNoIdAsksToBeFoundByItsType() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(assoc 'id (make-part-list-block))") == .false)
        #expect(
            try engine.evaluate("(eq? 'part-list (cdr (assoc 'type (make-part-list-block))))")
                == .true)
    }
}
