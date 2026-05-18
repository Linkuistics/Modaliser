import Testing
import LispKit
@testable import Modaliser

@Suite("Window Library")
struct WindowLibraryTests {

    // MARK: - Library registration

    @Test func windowLibraryFunctionsExist() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("list-windows")
        _ = try engine.evaluate("focus-window")
        _ = try engine.evaluate("center-window")
        _ = try engine.evaluate("move-window")
        _ = try engine.evaluate("toggle-fullscreen")
        _ = try engine.evaluate("restore-window")
    }

    // MARK: - Procedure checks

    @Test func listWindowsIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? list-windows)") == .true)
    }

    @Test func focusWindowIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? focus-window)") == .true)
    }

    @Test func centerWindowIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? center-window)") == .true)
    }

    @Test func moveWindowIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? move-window)") == .true)
    }

    @Test func toggleFullscreenIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? toggle-fullscreen)") == .true)
    }

    @Test func restoreWindowIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? restore-window)") == .true)
    }

    // MARK: - list-windows

    @Test func listWindowsReturnsList() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(list-windows)")
        // Should return a list (pair or null)
        switch result {
        case .pair, .null: break
        default: Issue.record("Expected list, got \(result)")
        }
    }

    // MARK: - WindowInfo

    @Test func windowCacheReturnsWindows() {
        let windows = WindowCache.shared.listWindows()
        // Should return an array (may be empty in CI, but shouldn't crash)
        #expect(windows.count >= 0)
    }

    @Test func windowInfoHasRequiredFields() {
        let windows = WindowCache.shared.listWindows()
        for window in windows {
            // title is always set (window title or app name)
            #expect(!window.title.isEmpty)
            // windowId can be 0 for other-space app-level entries
            // ownerName should be present
            #expect(!window.ownerName.isEmpty)
        }
    }

    @Test func listCurrentSpaceWindowsExposesBounds() throws {
        // Smoke test: function exists, returns a list whose entries (if any)
        // carry x/y/w/h. Can't assert specific windows in a unit test, so
        // assert structural shape.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser window))")
        try engine.evaluate("(define ws (list-current-space-windows))")
        let isList = try engine.evaluate("(list? ws)")
        #expect(isList == .true)
        try engine.evaluate("""
          (define has-bounds-shape?
            (let loop ((xs ws))
              (cond ((null? xs) #t)
                    ((not (and (assoc 'x (car xs))
                               (assoc 'y (car xs))
                               (assoc 'w (car xs))
                               (assoc 'h (car xs))
                               (assoc 'windowId (car xs))
                               (assoc 'ownerPid (car xs)))) #f)
                    (else (loop (cdr xs))))))
        """)
        #expect(try engine.evaluate("has-bounds-shape?") == .true)
    }
}
