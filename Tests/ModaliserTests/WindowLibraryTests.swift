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

    @Test func findChipPositionIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? find-chip-position)") == .true)
    }

    @Test func focusedWindowIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? focused-window)") == .true)
    }

    @Test func listDisplaysIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? list-displays)") == .true)
    }

    @Test func setFocusedWindowFrameIsProcedure() throws {
        // Mutator — existence check only; calling it would move a real window.
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? set-focused-window-frame)") == .true)
    }

    @Test func focusDisplayIsProcedure() throws {
        // Mutator — existence check only; calling it would warp the mouse /
        // raise a real window in the user's live session.
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? focus-display)") == .true)
    }

    @Test func listDisplaysReturnsWellFormedAlists() throws {
        // Read-only primitive — safe to call. Assert structural shape and
        // left-to-right (ascending x) ordering without asserting a concrete
        // display count (CI may have 0 or 1 screen).
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser window))")
        try engine.evaluate("(define ds (list-displays))")
        #expect(try engine.evaluate("(list? ds)") == .true)
        try engine.evaluate("""
          (define well-formed?
            (let loop ((xs ds))
              (cond ((null? xs) #t)
                    ((not (and (assoc 'id (car xs)) (assoc 'x (car xs))
                               (assoc 'y (car xs)) (assoc 'w (car xs))
                               (assoc 'h (car xs)) (assoc 'is-primary (car xs)))) #f)
                    (else (loop (cdr xs))))))
          (define ordered?
            (let loop ((xs ds) (prev #f))
              (cond ((null? xs) #t)
                    ((and prev (< (cdr (assoc 'x (car xs))) prev)) #f)
                    (else (loop (cdr xs) (cdr (assoc 'x (car xs))))))))
        """)
        #expect(try engine.evaluate("well-formed?") == .true)
        #expect(try engine.evaluate("ordered?") == .true)
    }

    @Test func focusedWindowReturnsAlistOrFalse() throws {
        // Smoke: with no deterministic frontmost window in CI, (focused-window)
        // returns #f (nothing focused / AX unavailable) or the full identity
        // alist. Assert the shape — pid + windowId + x/y/w/h — without
        // asserting any concrete window. Mirrors findChipPositionReturnsAlistOrFalse.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser window))")
        try engine.evaluate("(define f (focused-window))")
        #expect(try engine.evaluate("""
          (or (eq? f #f)
              (and (pair? f)
                   (assoc 'ownerPid f) (assoc 'windowId f)
                   (assoc 'x f) (assoc 'y f) (assoc 'w f) (assoc 'h f)
                   #t))
        """) == .true)
    }

    @Test func findChipPositionReturnsAlistOrFalse() throws {
        // Smoke: synthetic (wid, pid) won't match any real window, so the
        // target-not-found path returns the natural origin. Assert
        // structural shape — alist with x and y entries — without
        // asserting specific coordinates (CGWindowList state isn't
        // deterministic in CI).
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser window))")
        try engine.evaluate("""
          (define p (find-chip-position 999999999 999999999
                                        0 0 1000 800
                                        20 16
                                        24 24 4))
        """)
        #expect(try engine.evaluate(
            "(or (eq? p #f) (and (pair? p) (assoc 'x p) (assoc 'y p) #t))"
        ) == .true)
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
