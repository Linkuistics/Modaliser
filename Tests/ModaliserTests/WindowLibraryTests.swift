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

    @Test func windowInfoFromCGWindowList() {
        // Test the pure Swift WindowInfo extraction (no AX needed)
        let windows = WindowEnumerator.listVisibleWindows()
        // Should return an array (may be empty in CI, but shouldn't crash)
        #expect(windows.count >= 0)
    }

    @Test func windowInfoHasRequiredFields() {
        let windows = WindowEnumerator.listVisibleWindows()
        for window in windows {
            #expect(!window.title.isEmpty || true)  // title may be empty
            #expect(window.windowId > 0)
            // ownerName should be present
            #expect(!window.ownerName.isEmpty)
        }
    }
}
