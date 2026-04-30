import Testing
import LispKit
@testable import Modaliser

@Suite("App Library")
struct AppLibraryTests {

    // MARK: - Helpers

    private func isList(_ expr: Expr) -> Bool {
        switch expr {
        case .pair: return true
        case .null: return true
        default: return false
        }
    }

    // MARK: - Library registration

    @Test func appLibraryFunctionsExist() throws {
        let engine = try SchemeEngine()
        // These should not throw — functions are registered
        _ = try engine.evaluate("find-installed-apps")
        _ = try engine.evaluate("activate-app")
        _ = try engine.evaluate("reveal-in-finder")
        _ = try engine.evaluate("open-with")
        _ = try engine.evaluate("launch-app")
        _ = try engine.evaluate("open-url")
    }

    // MARK: - find-installed-apps

    @Test func findInstalledAppsReturnsList() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(find-installed-apps)")
        #expect(isList(result))
    }

    @Test func findInstalledAppsEachEntryHasTextAndPath() throws {
        let engine = try SchemeEngine()
        // Get first entry and check it has 'text' and 'path' keys
        let result = try engine.evaluate("""
            (let ((apps (find-installed-apps)))
              (if (pair? apps)
                (let ((first (car apps)))
                  (list (cdr (assoc 'text first))
                        (cdr (assoc 'path first))))
                (list "" "")))
            """)
        // Result should be a list of two strings
        if case .pair = result { } else { Issue.record("Expected pair, got \(result)") }
    }

    @Test func findInstalledAppsEntriesHaveBundleId() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("""
            (let ((apps (find-installed-apps)))
              (if (pair? apps)
                (let ((first (car apps)))
                  (assoc 'bundleId first))
                #f))
            """)
        // assoc returns the pair (bundleId . value) or #f if not found
        if case .pair = result { } else { Issue.record("Expected pair for bundleId assoc, got \(result)") }
    }

    @Test func findInstalledAppsEntriesHaveIconFields() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("""
            (let ((apps (find-installed-apps)))
              (if (pair? apps)
                (let ((first (car apps)))
                  (list (cdr (assoc 'icon first))
                        (cdr (assoc 'iconType first))))
                #f))
            """)
        if case .pair = result { } else { Issue.record("Expected pair for icon fields, got \(result)") }
    }

    @Test func findInstalledAppsSortedAlphabetically() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("""
            (let ((apps (find-installed-apps)))
              (if (pair? apps)
                (if (pair? (cdr apps))
                  (let ((first-name (cdr (assoc 'text (car apps))))
                        (second-name (cdr (assoc 'text (car (cdr apps))))))
                    (string<=? first-name second-name))
                  #t)
                #t))
            """)
        #expect(result == .true)
    }

    // MARK: - Procedure checks

    @Test func launchAppIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? launch-app)") == .true)
    }

    @Test func activateAppIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? activate-app)") == .true)
    }

    @Test func revealInFinderIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? reveal-in-finder)") == .true)
    }

    @Test func openWithIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? open-with)") == .true)
    }

    @Test func openUrlIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? open-url)") == .true)
    }

    // MARK: - focused-app-bundle-id

    @Test func focusedAppBundleIdIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? focused-app-bundle-id)") == .true)
    }

    @Test func focusedAppBundleIdReturnsStringOrFalse() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(focused-app-bundle-id)")
        // In a test runner context, there may or may not be a frontmost app
        if case .false = result { return }
        // Otherwise should be a string
        _ = try result.asString()
    }

    @Test func appDisplayNameResolvesKnownBundleId() throws {
        let engine = try SchemeEngine()
        // Finder is guaranteed to be installed and Launch Services-registered on macOS.
        let result = try engine.evaluate("(app-display-name \"com.apple.finder\")").asString()
        #expect(result == "Finder")
    }

    @Test func appDisplayNameReturnsFalseForUnknownBundleId() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(app-display-name \"com.nonexistent.fake-bundle-id-zzz\")")
        #expect(result == .false)
    }
}
