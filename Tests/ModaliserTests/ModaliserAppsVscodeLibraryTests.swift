import Foundation
import Testing

@testable import Modaliser

// Unit tests for the (modaliser apps vscode) library — the utilities
// layer behind the F17 VSCode screen (vscode-screen-k2).
//
// Every behavioural assertion lands on the PURE half — project-name,
// windows-of, focus-choice — which takes the window enumeration as an
// argument. Nothing here runs an accessibility sweep or posts a
// keystroke: window-source and the three chord thunks are asserted to
// RESOLVE and are never called, the same discipline the dia suite keeps
// (ADR-0023 — the suite reaches nothing outside the process).
@Suite("(modaliser apps vscode) library")
struct ModaliserAppsVscodeLibraryTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (prefix (modaliser apps vscode) code:))")
        // A fixture enumeration in `list-windows`' own shape: 'text is the
        // window title, 'icon the bundle id. Two VSCode windows — one with
        // a file open, one without — plus a foreign window that must not
        // survive the filter, and a second VSCode-owned window whose title
        // carries an em dash inside the FOLDER name, which is the case a
        // character-class split would get wrong.
        try engine.evaluate("""
          (define fixture
            (list
              (list (cons 'text "vscode.sld — Modaliser.local-tree-for-vscode")
                    (cons 'subText "Code") (cons 'icon "com.microsoft.VSCode")
                    (cons 'windowId 16489) (cons 'ownerPid 12040))
              (list (cons 'text "InTheLoop")
                    (cons 'subText "Code") (cons 'icon "com.microsoft.VSCode")
                    (cons 'windowId 16490) (cons 'ownerPid 12040))
              (list (cons 'text "Inbox — Mail")
                    (cons 'subText "Mail") (cons 'icon "com.apple.mail")
                    (cons 'windowId 900) (cons 'ownerPid 501))))
        """)
        return engine
    }

    // The exports resolve. Structural only for the impure four:
    // window-source sweeps the live window list and the chords post
    // keystrokes, so none may fire here.
    @Test func exportsResolveAsProcedures() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(procedure? code:window-source)") == .true)
        #expect(try engine.evaluate("(procedure? code:focus-window!)") == .true)
        #expect(try engine.evaluate("(procedure? code:windows-of)") == .true)
        #expect(try engine.evaluate("(procedure? code:project-name)") == .true)
        #expect(try engine.evaluate("(procedure? code:focus-choice)") == .true)
        #expect(try engine.evaluate("(procedure? code:toggle-terminal)") == .true)
        #expect(try engine.evaluate("(procedure? code:focus-explorer)") == .true)
        #expect(try engine.evaluate("(procedure? code:focus-editor)") == .true)
        #expect(try engine.evaluate("(procedure? code:previous-editor)") == .true)
        #expect(try engine.evaluate("(procedure? code:next-editor)") == .true)
        #expect(try engine.evaluate("(procedure? code:editor-cycler)") == .true)
        #expect(try engine.evaluate("(procedure? code:cycle-thunk)") == .true)
    }

    // The bundle id is VSCode's own fact and is what the filter keys on,
    // so it is pinned rather than left to a comment.
    @Test func bundleIdIsVscodes() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? code:bundle-id "com.microsoft.VSCode")
        """) == .true)
    }

    // A title's last spaced-em-dash segment is the folder. A title with
    // no separator IS the folder (nothing open in the editor), and the
    // empty title maps to itself rather than raising.
    @Test func projectNameTakesTheLastEmDashSegment() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (code:project-name "vscode.sld — Modaliser.local-tree-for-vscode")
                  "Modaliser.local-tree-for-vscode")
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (code:project-name "InTheLoop") "InTheLoop")
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (code:project-name "") "")
        """) == .true)
    }

    // Only the SPACED em dash separates. A folder or file name may hold a
    // hyphen or an unspaced dash of its own, and neither is a segment
    // boundary — the reason the split is on a literal rather than on a
    // dash character class.
    @Test func projectNameSplitsOnlyOnTheSpacedEmDash() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (code:project-name "main.rs — grove.add-user-guide")
                  "grove.add-user-guide")
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (code:project-name "a—b") "a—b")
        """) == .true)
    }

    // The filter is a bundle-id test, so the foreign window is dropped
    // and both VSCode windows survive.
    @Test func windowsOfKeepsOnlyVscodeWindows() throws {
        let engine = try loaded()
        try engine.evaluate("(define items (code:windows-of fixture))")
        #expect(try engine.evaluate("(= (length items) 2)") == .true)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'windowId i))) items)
                  '(16490 16489))
        """) == .true)
    }

    // Alphabetical by project, NOT enumeration order. The enumeration is
    // front-to-back stacking order, so it changes every time a window is
    // focused — and a chooser whose rows move between presses cannot be
    // learned. The fixture is deliberately out of alphabetical order
    // ("Modaliser…" before "InTheLoop"), so a pass-through would fail
    // here.
    @Test func windowsOfIsAlphabeticalByProject() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'text i))) (code:windows-of fixture))
                  '("InTheLoop" "Modaliser.local-tree-for-vscode"))
        """) == .true)
    }

    // Case-insensitive, because a human reading folder names is not
    // thinking in ASCII: a plain `string<?` would sort every capitalised
    // name ahead of every lowercase one, scattering the list.
    @Test func windowsOfSortsCaseInsensitively() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define mixed-case
            (map (lambda (t)
                   (list (cons 'text t) (cons 'icon "com.microsoft.VSCode")
                         (cons 'windowId 1) (cons 'ownerPid 1)))
                 '("zebra" "Apple" "banana")))
        """)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'text i))) (code:windows-of mixed-case))
                  '("Apple" "banana" "zebra"))
        """) == .true)
    }

    // The order is TOTAL: names differing only in case are separated by
    // a case-sensitive tie-break, so they cannot swap places between
    // presses either — which is the whole point of sorting at all.
    @Test func windowsOfOrdersCaseVariantsDeterministically() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define variants
            (map (lambda (t)
                   (list (cons 'text t) (cons 'icon "com.microsoft.VSCode")
                         (cons 'windowId 1) (cons 'ownerPid 1)))
                 '("repo" "Repo" "REPO")))
        """)
        // Whatever the tie-break's direction, the two orderings must agree.
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'text i))) (code:windows-of variants))
                  (map (lambda (i) (cdr (assoc 'text i)))
                       (code:windows-of (reverse variants))))
        """) == .true)
    }

    // 'text is the chooser's display and fuzzy-match field, so it carries
    // the PROJECT; the untouched title stays beside it under 'title.
    // Both halves matter: the first is what the human reads, the second
    // is what a window→directory resolver has to join on.
    @Test func windowsOfShowsTheProjectAndKeepsTheTitle() throws {
        let engine = try loaded()
        try engine.evaluate("(define items (code:windows-of fixture))")
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'text i))) items)
                  '("InTheLoop" "Modaliser.local-tree-for-vscode"))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'title i))) items)
                  '("InTheLoop" "vscode.sld — Modaliser.local-tree-for-vscode"))
        """) == .true)
    }

    // The choice alist focus-window reads. 'ownerPid must be present —
    // without it focus-window silently no-ops — and 'text must be the
    // REAL title, because that is the fallback when the window id fails
    // to resolve against the live sweep. A choice carrying the display
    // text would degrade that fallback to never matching, which is the
    // failure this test exists to catch.
    @Test func focusChoiceCarriesThePidAndTheRealTitle() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define choice
            (code:focus-choice (cadr (code:windows-of fixture))))
        """)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'ownerPid choice)) 12040)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'windowId choice)) 16489)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'text choice))
                  "vscode.sld — Modaliser.local-tree-for-vscode")
        """) == .true)
    }

    // An empty enumeration is the ordinary "VSCode is not running" case
    // and yields an empty chooser, never an error reaching a leader press.
    @Test func windowsOfDegradesToEmpty() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(null? (code:windows-of '()))") == .true)
    }
}

// MARK: - The workspace surface (grove-leaf-reveal-k3)

/// Tests for the half of `(modaliser apps vscode)` that answers "which
/// DIRECTORY is this window rooted at" — the state-file reader, the
/// title join, and the open-and-reveal command.
///
/// Every assertion lands on the pure half, over the state file's TEXT.
/// Nothing here reads `~/Library`, and nothing spawns: `reveal-file!`
/// goes through the shell seam's async runner, installed canned
/// (ADR-0023).
@Suite("(modaliser apps vscode) workspace surface")
struct ModaliserAppsVscodeWorkspaceTests {

    /// The fixture: `windowsState`, captured VERBATIM out of a real
    /// `storage.json` (VSCode 1.136.2) and wrapped as a document of its
    /// own. Trimmed of the ~96 KB of unrelated keys around it and
    /// otherwise untouched — a hand-written approximation would test
    /// the approximation.
    ///
    /// Two things in it are load-bearing and are the reason the real
    /// capture beats a tidy one. `lastActiveWindow` and
    /// `lastPluginDevelopmentHostWindow` BOTH carry a `folder` key, and
    /// both come BEFORE `openedWindows` in the document — so a reader
    /// that hunted for folders rather than for the array would answer
    /// with the wrong window, and `prince-live-test` (which is not open
    /// at all) is the tell that it did.
    private static let stateFile = """
          {
              "windowsState": {
                  "lastActiveWindow": {
                      "folder": "file:///Users/antony/Development/Modaliser.local-tree-for-vscode",
                      "backupPath": "/Users/antony/Library/Application Support/Code/Backups/a1edbf86d5745e35deb55758f29ab97c",
                      "uiState": {
                          "mode": 1,
                          "x": 1706,
                          "y": 31,
                          "width": 3413,
                          "height": 2129,
                          "zoomLevel": 1
                      }
                  },
                  "lastPluginDevelopmentHostWindow": {
                      "folder": "file:///Users/antony/Development/YesLogic/prince-live-test",
                      "uiState": {
                          "mode": 1,
                          "x": 551,
                          "y": 157,
                          "width": 2439,
                          "height": 1991,
                          "zoomLevel": 1
                      }
                  },
                  "openedWindows": [
                      {
                          "folder": "file:///Users/antony/Development/grove.add-user-guide-and-code-walkthoughs-for-all-crates",
                          "backupPath": "/Users/antony/Library/Application Support/Code/Backups/47d0542b67a022229b787d7e21559e84",
                          "uiState": {
                              "mode": 1,
                              "x": 1706,
                              "y": 31,
                              "width": 3413,
                              "height": 2129,
                              "zoomLevel": 1
                          }
                      },
                      {
                          "folder": "file:///Users/antony/Development/APIAnyware.add-ocaml-target",
                          "backupPath": "/Users/antony/Library/Application Support/Code/Backups/8a84a9c9333ecd1af68cbff434913bdd",
                          "uiState": {
                              "mode": 1,
                              "x": 1706,
                              "y": 31,
                              "width": 3413,
                              "height": 2129,
                              "zoomLevel": 1
                          }
                      },
                      {
                          "folder": "file:///Users/antony/Development/InTheLoop",
                          "backupPath": "/Users/antony/Library/Application Support/Code/Backups/4908051e56d3aff259434ef038ae0e7c",
                          "uiState": {
                              "mode": 1,
                              "x": 1706,
                              "y": 31,
                              "width": 3413,
                              "height": 2129,
                              "zoomLevel": 1
                          }
                      },
                      {
                          "folder": "file:///Users/antony/Development/Modaliser.local-tree-for-vscode",
                          "backupPath": "/Users/antony/Library/Application Support/Code/Backups/a1edbf86d5745e35deb55758f29ab97c",
                          "uiState": {
                              "mode": 1,
                              "x": 1706,
                              "y": 31,
                              "width": 3413,
                              "height": 2129,
                              "zoomLevel": 1
                          }
                      }
                  ]
              }
          }
        """

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (prefix (modaliser apps vscode) code:)
                  (only (modaliser util) string-contains?))
        """)
        try engine.evaluate("""
          (define state-text \(Self.schemeLiteral(Self.stateFile)))
          (define workspaces (code:workspaces-of state-text))
        """)
        return engine
    }

    /// A Swift string as Scheme source. The fixture is multi-line and
    /// LispKit's reader rejects a raw newline inside a literal.
    private static func schemeLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: Surface

    @Test func exportsResolveAsProcedures() throws {
        let engine = try loaded()
        for name in ["focused-workspace-path", "open-workspaces", "state-file-path",
                     "workspaces-of", "opened-windows-json", "workspace-for-title",
                     "title-of-window-id", "reveal-file!", "open-file-command"] {
            #expect(try engine.evaluate("(procedure? code:\(name))") == .true,
                    "code:\(name) should resolve")
        }
    }

    /// `state-file-path` is where VSCode actually keeps it. Asserted on
    /// the tail rather than the whole string: `$HOME` is the machine's.
    @Test func stateFilePathIsVscodesGlobalStorage() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (let* ((p (code:state-file-path))
                 (tail "/Library/Application Support/Code/User/globalStorage/storage.json")
                 (n (string-length p)) (m (string-length tail)))
            (and (> n m) (string=? (substring p (- n m) n) tail)))
        """) == .true)
    }

    // MARK: Slicing the array out

    /// The slice is the `openedWindows` array and only that — it starts
    /// at its `[` and ends at its `]`, so what json-parse sees is ~400
    /// bytes rather than the whole file. That is the 899 ms the library
    /// header records, and it is why this is asserted rather than left
    /// as an implementation detail.
    @Test func openedWindowsJsonSlicesJustTheArray() throws {
        let engine = try loaded()
        try engine.evaluate("(define slice (code:opened-windows-json state-text))")
        #expect(try engine.evaluate("""
          (and (char=? (string-ref slice 0) #\\[)
               (char=? (string-ref slice (- (string-length slice) 1)) #\\]))
        """) == .true)
        #expect(try engine.evaluate("(< (string-length slice) (string-length state-text))") == .true)
        // The decoy folders live outside the array and must not be in it.
        #expect(try engine.evaluate("""
          (string-contains? slice "prince-live-test")
        """) == .false)
    }

    /// The slicer anchors on `windowsState` first, so an `openedWindows`
    /// appearing earlier as ordinary stored TEXT cannot shadow the real
    /// array. Storage files hold arbitrary extension state, so this is a
    /// realistic shadow, not a contrived one.
    @Test func openedWindowsJsonIgnoresAnEarlierDecoyKey() throws {
        let engine = try loaded()
        let decoy = #"{"some.extension": "a note mentioning \"openedWindows\": [1,2,3]", "#
        try engine.evaluate("""
          (define decoyed
            (string-append \(Self.schemeLiteral(decoy))
                           (substring state-text 1 (string-length state-text))))
        """)
        #expect(try engine.evaluate("""
          (equal? (code:opened-windows-json decoyed)
                  (code:opened-windows-json state-text))
        """) == .true)
    }

    /// A `]` inside a string is text, not the end of the array. Without
    /// the scanner's string-awareness the slice would be cut short and
    /// json-parse would see a truncated array.
    @Test func openedWindowsJsonIgnoresBracketsInsideStrings() throws {
        let engine = try loaded()
        let bracketed = """
          {"windowsState": {"openedWindows": [
             {"folder": "file:///tmp/a]b"},
             {"folder": "file:///tmp/plain"}]}}
          """
        try engine.evaluate("(define bracketed \(Self.schemeLiteral(bracketed)))")
        #expect(try engine.evaluate("""
          (equal? (map (lambda (w) (cdr (assoc 'path w)))
                       (code:workspaces-of bracketed))
                  '("/tmp/a]b" "/tmp/plain"))
        """) == .true)
    }

    /// Text with no state at all — an empty file, a file VSCode has not
    /// written yet, or a format change that dropped the key — degrades
    /// to no workspaces rather than raising into a leader press.
    @Test func missingOrMalformedStateDegradesToEmpty() throws {
        let engine = try loaded()
        #expect(try engine.evaluate(#"(equal? (code:opened-windows-json "") "")"#) == .true)
        #expect(try engine.evaluate(#"(null? (code:workspaces-of ""))"#) == .true)
        for text in [
            #"{"windowsState": {}}"#,
            // The key is there but its value is not an array — a format change.
            #"{"windowsState": {"openedWindows": {}}}"#,
            // A truncated document: the array opens and never closes.
            #"{"windowsState": {"openedWindows": [{"folder""#,
            // Not JSON at all.
            "half a file",
        ] {
            #expect(try engine.evaluate(
                "(null? (code:workspaces-of \(Self.schemeLiteral(text))))") == .true,
                "should degrade to empty: \(text)")
        }
    }

    // MARK: Reading the real capture

    /// The four windows that were actually open, in the file's order,
    /// with their exact paths. `prince-live-test` is the decoy and must
    /// be absent.
    @Test func workspacesOfReadsTheOpenedWindowsOnly() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (map (lambda (w) (cdr (assoc 'path w))) workspaces)
                  '("/Users/antony/Development/grove.add-user-guide-and-code-walkthoughs-for-all-crates"
                    "/Users/antony/Development/APIAnyware.add-ocaml-target"
                    "/Users/antony/Development/InTheLoop"
                    "/Users/antony/Development/Modaliser.local-tree-for-vscode"))
        """) == .true)
    }

    /// 'name is the folder's basename — the join key, and the only thing
    /// a window title can be matched against.
    @Test func workspacesOfNamesEachFolder() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (map (lambda (w) (cdr (assoc 'name w))) workspaces)
                  '("grove.add-user-guide-and-code-walkthoughs-for-all-crates"
                    "APIAnyware.add-ocaml-target"
                    "InTheLoop"
                    "Modaliser.local-tree-for-vscode"))
        """) == .true)
    }

    /// Entries with no local folder are absent rather than present-and-
    /// broken: an empty window has no `folder` key, a multi-root window
    /// carries a `workspace` instead, and a remote window's folder is
    /// not on this machine. Hand-written, unlike the capture above —
    /// the developer's real file happened to hold none of the three.
    @Test func workspacesOfSkipsWindowsWithNoLocalFolder() throws {
        let engine = try loaded()
        let mixed = """
          {"windowsState": {"openedWindows": [
             {"backupPath": "/tmp/x"},
             {"workspace": {"id": "9", "configPath": "file:///tmp/m.code-workspace"}},
             {"folder": "vscode-remote://ssh-remote%2Bbox/home/me/proj"},
             {"folder": "file:///Users/me/real"}]}}
          """
        try engine.evaluate("(define mixed \(Self.schemeLiteral(mixed)))")
        #expect(try engine.evaluate("""
          (equal? (map (lambda (w) (cdr (assoc 'path w))) (code:workspaces-of mixed))
                  '("/Users/me/real"))
        """) == .true)
    }

    /// Percent-decoding, and specifically decoding a RUN of escapes as
    /// one UTF-8 sequence. VSCode encodes a URI byte by byte, so "café"
    /// arrives as two escapes that are one character — decoded
    /// separately they would be two replacement characters, and the
    /// folder name is the join key, so a mangled one stops matching its
    /// window silently.
    @Test func workspacesOfPercentDecodesFolderUris() throws {
        let engine = try loaded()
        let encoded = """
          {"windowsState": {"openedWindows": [
             {"folder": "file:///Users/me/My%20Work/caf%C3%A9"}]}}
          """
        try engine.evaluate("(define encoded \(Self.schemeLiteral(encoded)))")
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'path (car (code:workspaces-of encoded))))
                  "/Users/me/My Work/café")
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'name (car (code:workspaces-of encoded)))) "café")
        """) == .true)
    }

    // MARK: The join

    /// The ordinary case: a title's last em-dash segment is the folder,
    /// and the PATH comes from the state file, never from the title.
    @Test func workspaceForTitleJoinsOnTheFolderSegment() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'path
                    (code:workspace-for-title
                      "vscode.sld — Modaliser.local-tree-for-vscode" workspaces)))
                  "/Users/antony/Development/Modaliser.local-tree-for-vscode")
        """) == .true)
        // No separator at all — nothing open in the editor.
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'path (code:workspace-for-title "InTheLoop" workspaces)))
                  "/Users/antony/Development/InTheLoop")
        """) == .true)
    }

    /// EVERY segment is tested, not just the last. Under a named profile
    /// VSCode appends the profile after the folder, so the folder is the
    /// second-to-last segment — the caveat vscode-screen-k2 recorded and
    /// deliberately did not engineer around in `project-name`. This is
    /// where it is paid for.
    @Test func workspaceForTitleTestsEverySegment() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'path
                    (code:workspace-for-title
                      "vscode.sld — InTheLoop — Work Profile" workspaces)))
                  "/Users/antony/Development/InTheLoop")
        """) == .true)
    }

    /// A window whose folder is not in the state file — it opened since
    /// the file was last written, which is an ordinary occurrence given
    /// that VSCode writes on state change — is #f, not an error.
    @Test func workspaceForTitleMissesQuietly() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (code:workspace-for-title "main.rs — SomethingElse" workspaces)
        """) == .false)
        #expect(try engine.evaluate("(code:workspace-for-title \"\" workspaces)") == .false)
        #expect(try engine.evaluate("(code:workspace-for-title \"InTheLoop\" '())") == .false)
    }

    /// The live half's join key is the window id, and the enumeration is
    /// filtered to VSCode first, so an identically-titled window of
    /// another app cannot answer.
    @Test func titleOfWindowIdFindsTheVscodeWindow() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define fixture
            (list
              (list (cons 'text "vscode.sld — Modaliser.local-tree-for-vscode")
                    (cons 'icon "com.microsoft.VSCode")
                    (cons 'windowId 16489) (cons 'ownerPid 12040))
              (list (cons 'text "Inbox — Mail")
                    (cons 'icon "com.apple.mail")
                    (cons 'windowId 900) (cons 'ownerPid 501))))
        """)
        #expect(try engine.evaluate("""
          (equal? (code:title-of-window-id 16489 fixture)
                  "vscode.sld — Modaliser.local-tree-for-vscode")
        """) == .true)
        #expect(try engine.evaluate("(code:title-of-window-id 900 fixture)") == .false)
        #expect(try engine.evaluate("(code:title-of-window-id 99999 fixture)") == .false)
    }

    /// Window id 0 is the enumeration's "could not resolve" sentinel
    /// (`_AXUIElementGetWindow` failed). It must never match, or a
    /// cold-AX miss on the focused window would join it to whichever
    /// other window also failed to resolve.
    @Test func titleOfWindowIdRejectsTheZeroSentinel() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define unresolved
            (list (list (cons 'text "Something — Elsewhere")
                        (cons 'icon "com.microsoft.VSCode")
                        (cons 'windowId 0) (cons 'ownerPid 12040))))
        """)
        #expect(try engine.evaluate("(code:title-of-window-id 0 unresolved)") == .false)
    }

    // MARK: Opening

    /// The command is a bare `code <path>`, single-quoted. No `-r` and
    /// no `-n`: `-r` forces the LAST ACTIVE window, which is exactly the
    /// window this operation is trying not to use, and `-n` a new one.
    /// A bare invocation is what routes the file to the window owning
    /// its folder (see the library header).
    @Test func openFileCommandIsBareCodeWithAQuotedPath() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define cmd (code:open-file-command "/Users/me/proj/.grove/03-impl--x-k3.md"))
          (import (only (modaliser util) string-contains?))
        """)
        #expect(try engine.evaluate("""
          (string-contains? cmd "code '/Users/me/proj/.grove/03-impl--x-k3.md' 2>/dev/null")
        """) == .true)
        #expect(try engine.evaluate(#"(string-contains? cmd " -r ")"#) == .false)
        #expect(try engine.evaluate(#"(string-contains? cmd " -n ")"#) == .false)
        // The PATH preamble every CLI-driven module bakes (ADR-0017).
        #expect(try engine.evaluate(#"(string-contains? cmd "export PATH=")"#) == .true)
    }

    /// A path with a quote in it stays one shell word. Not hypothetical
    /// enough to skip: the path is arbitrary text out of an editor's
    /// stored state, and an unescaped quote here is a command-injection
    /// site, not just a broken open.
    ///
    /// Asserted on the ESCAPE rather than on the absence of the payload:
    /// the payload text is still *in* the command — harmlessly, inside a
    /// quoted word — so "does not contain it" would be a test that
    /// passes for the wrong reason. What matters is that every `'` in
    /// the path arrives as the `'\''` idiom.
    @Test func openFileCommandEscapesQuotes() throws {
        let engine = try loaded()
        try engine.evaluate(#"""
          (define cmd (code:open-file-command "/tmp/it's; touch /tmp/pwned; .md"))
        """#)
        #expect(try engine.evaluate(#"""
          (string-contains? cmd "code '/tmp/it'\\''s; touch /tmp/pwned; .md'")
        """#) == .true)
    }

    /// `reveal-file!` spawns through the ASYNC runner, not the
    /// synchronous one: `code` against a running instance takes ~1.1 s
    /// to return, and holding the thread that owns the CGEvent tap for
    /// that long is ADR-0014's stalled-tap hazard.
    ///
    /// The canned runner records the command and DOES NOT invoke the
    /// callback, deliberately: the callback's body is the explorer
    /// chord, and `(modaliser input)` has no seam — calling it would
    /// post a real shift-cmd-e into whatever app the developer has
    /// focused (ADR-0023, and the discipline the suite above keeps for
    /// the three chord thunks). That the chord fires *after* the open
    /// is therefore structural — it is inside the callback — rather
    /// than asserted here.
    @Test func revealFileGoesThroughTheAsyncSeam() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (import (modaliser shell))
          (define spawned '())
          (define sync-spawned '())
          (current-shell-runner
            (lambda (cmd) (set! sync-spawned (cons cmd sync-spawned)) ""))
          (current-shell-async-runner
            (lambda (cmd cb . opts) (set! spawned (cons cmd spawned))))
          (code:reveal-file! "/Users/me/proj/leaf.md")
        """)
        #expect(try engine.evaluate("(= (length spawned) 1)") == .true)
        #expect(try engine.evaluate("(null? sync-spawned)") == .true)
        #expect(try engine.evaluate("""
          (equal? (car spawned) (code:open-file-command "/Users/me/proj/leaf.md"))
        """) == .true)
    }

    /// The follow-up is the caller's to supply. `focus-explorer` is
    /// VSCode's own shift-cmd-e, which is right for a stock install but
    /// bounces to the *editor* when the explorer already has focus — so
    /// anyone who has bound a strict-focus command of their own passes
    /// that instead, and preference stays out of the library
    /// (ADR-0021). Asserted with a plain recorder rather than a chord,
    /// which also shows that the follow-up runs from the callback.
    @Test func revealFileRunsACallerSuppliedFollowUp() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (import (modaliser shell))
          (define events '())
          (current-shell-async-runner
            (lambda (cmd cb . opts)
              (set! events (cons 'spawned events))
              (cb 0 "" "")))
          (code:reveal-file! "/Users/me/proj/leaf.md"
                             (lambda () (set! events (cons 'followed events))))
        """)
        #expect(try engine.evaluate("(equal? (reverse events) '(spawned followed))") == .true)
    }

    /// A resolution that failed passes straight through: nothing spawns
    /// and no chord fires, so a caller may hand `focused-workspace-path`
    /// #f without guarding it.
    @Test func revealFileDoesNothingWithoutAPath() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (import (modaliser shell))
          (define spawned '())
          (current-shell-async-runner
            (lambda (cmd cb . opts) (set! spawned (cons cmd spawned))))
          (code:reveal-file! "")
          (code:reveal-file! #f)
        """)
        #expect(try engine.evaluate("(null? spawned)") == .true)
    }

    // ─── Cycling the editor (vscode-editor-cycling-k5) ──────────────
    //
    // `editor-cycler` is the one op the leaf's focus-first clause
    // needed, and its whole behaviour is ORDER: focus, then cycle.
    // Both halves are seams (`'focus`, `'cycle`) precisely so a test
    // can watch that order without posting a real keystroke — the same
    // discipline `'enumerate` gives `project-provider` (ADR-0023).

    /// The order is the behaviour. VSCode's cycle command changes the
    /// tab while leaving focus in the terminal or the explorer, so a
    /// cycler that fired them the other way round — or dropped the
    /// focus half — would look identical at the import and be wrong at
    /// every press.
    @Test func editorCyclerFocusesBeforeCycling() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define events '())
          (define cycle-prev
            (code:editor-cycler 'previous
              'focus (lambda () (set! events (cons 'focused events)))
              'cycle (lambda () (set! events (cons 'cycled events)))))
          (cycle-prev)
        """)
        #expect(try engine.evaluate("(equal? (reverse events) '(focused cycled))") == .true)
    }

    /// The constructor returns a thunk rather than acting, so a screen
    /// can hold it in a key slot exactly as it holds `focus-editor`.
    @Test func editorCyclerReturnsAThunkThatHasNotRunYet() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define ran '())
          (define op (code:editor-cycler 'next
                       'focus (lambda () (set! ran (cons 'f ran)))
                       'cycle (lambda () (set! ran (cons 'c ran)))))
        """)
        #expect(try engine.evaluate("(procedure? op)") == .true)
        #expect(try engine.evaluate("(null? ran)") == .true)
    }

    /// `'focus #f` drops the focus step — for a user whose cycle
    /// command already focuses, or who wants the bare chord. The cycle
    /// half still runs, which is what separates this from a no-op.
    @Test func editorCyclerWithFalseFocusSkipsTheFocusStep() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define events '())
          ((code:editor-cycler 'next
             'focus #f
             'cycle (lambda () (set! events (cons 'cycled events)))))
        """)
        #expect(try engine.evaluate("(equal? events '(cycled))") == .true)
    }

    /// The direction mapping, pinned where it is pure. `'previous` and
    /// `'next` must reach DIFFERENT chords — the failure this rules out
    /// is the copy-paste one, where both directions send the same key
    /// and the bug is invisible until you press the other bracket.
    @Test func cycleThunkMapsEachDirectionToItsOwnChord() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(procedure? (code:cycle-thunk 'previous))") == .true)
        #expect(try engine.evaluate("(procedure? (code:cycle-thunk 'next))") == .true)
        #expect(try engine.evaluate("(eq? (code:cycle-thunk 'previous) code:previous-editor)") == .true)
        #expect(try engine.evaluate("(eq? (code:cycle-thunk 'next) code:next-editor)") == .true)
        #expect(try engine.evaluate("(not (eq? (code:cycle-thunk 'previous) (code:cycle-thunk 'next)))") == .true)
    }

    /// An unrecognised direction resolves rather than raising: a screen
    /// is built at config-load time, and a mistyped symbol that failed
    /// the whole config would cost more than a key that cycles the
    /// wrong way and says so on the first press.
    @Test func cycleThunkTreatsAnUnknownDirectionAsNext() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(eq? (code:cycle-thunk 'sideways) code:next-editor)") == .true)
    }
}
