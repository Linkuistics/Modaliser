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
    // and both VSCode windows survive in enumeration order.
    @Test func windowsOfKeepsOnlyVscodeWindows() throws {
        let engine = try loaded()
        try engine.evaluate("(define items (code:windows-of fixture))")
        #expect(try engine.evaluate("(= (length items) 2)") == .true)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'windowId i))) items)
                  '(16489 16490))
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
                  '("Modaliser.local-tree-for-vscode" "InTheLoop"))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (i) (cdr (assoc 'title i))) items)
                  '("vscode.sld — Modaliser.local-tree-for-vscode" "InTheLoop"))
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
          (define choice (code:focus-choice (car (code:windows-of fixture))))
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
