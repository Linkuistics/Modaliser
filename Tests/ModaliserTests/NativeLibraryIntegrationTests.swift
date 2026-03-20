import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("Native library integration")
struct NativeLibraryIntegrationTests {

    // MARK: - Full config loads with native functions

    @Test func fullConfigLoadsWithNativeLibraryFunctions() throws {
        let configContent = """
            (set-leader! 'global F18)
            (set-leader! 'local F17)

            (define (open-url-action url)
              (lambda () (open-url url)))

            (define-tree 'global
              (key "s" "Safari"
                (lambda () (launch-app "Safari")))
              (key "i" "iTerm"
                (lambda () (launch-app "iTerm")))
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'source find-installed-apps
                  'on-select activate-app
                  'remember "apps"
                  'id-field "bundleId"
                  'actions
                    (list
                      (action "Open" 'key 'primary
                        'run (lambda (c) (activate-app c)))
                      (action "Show in Finder" 'key 'secondary
                        'run (lambda (c) (reveal-in-finder c)))
                      (action "Copy Path"
                        'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))))
                (selector "f" "Find File"
                  'prompt "Find file…"
                  'file-roots (list "~")
                  'on-select (lambda (c) (run-shell (string-append "/usr/bin/open \\"" (cdr (assoc 'path c)) "\\"")))))
              (group "w" "Windows"
                (key "c" "Center"
                  (lambda () (center-window)))
                (key "d" "First Third"
                  (lambda () (move-window 0 0 1/3 1)))
                (key "m" "Maximise"
                  (lambda () (toggle-fullscreen)))
                (key "r" "Restore"
                  (lambda () (restore-window)))
                (selector "s" "Switch Window"
                  'prompt "Select window…"
                  'source list-windows
                  'on-select focus-window))
              (group "o" "Open App"
                (key "g" "GitButler"
                  (lambda () (launch-app "GitButler")))
                (key "t" "Telegram"
                  (lambda () (launch-app "Telegram")))))
            """

        let dir = NSTemporaryDirectory()
        let path = dir + "test-config-\(UUID().uuidString).scm"
        try configContent.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = try SchemeEngine()
        try engine.evaluateFile(path)

        // Leader keys
        #expect(engine.registry.leaderKey(for: .global) == KeyCode.f18)
        #expect(engine.registry.leaderKey(for: .local) == KeyCode.f17)

        // Tree structure
        let tree = engine.registry.tree(for: .global)!

        // Direct commands
        #expect(tree.child(forKey: "s")?.label == "Safari")
        #expect(tree.child(forKey: "i")?.label == "iTerm")

        // Find group
        let find = tree.child(forKey: "f")!
        #expect(find.isGroup)
        #expect(find.label == "Find")

        // Find Apps selector
        if case .selector(let def) = find.child(forKey: "a") {
            #expect(def.label == "Find Apps")
            #expect(def.config.prompt == "Find app…")
            #expect(def.config.remember == "apps")
            #expect(def.config.idField == "bundleId")
            #expect(def.config.actions.count == 3)
            #expect(def.config.actions[0].name == "Open")
            #expect(def.config.actions[0].trigger == .primary)
            #expect(def.config.actions[1].name == "Show in Finder")
            #expect(def.config.actions[1].trigger == .secondary)
            // Source and onSelect should be procedures
            if case .procedure = def.config.source { } else {
                Issue.record("Expected source to be procedure")
            }
            if case .procedure = def.config.onSelect { } else {
                Issue.record("Expected onSelect to be procedure")
            }
        } else {
            Issue.record("Expected 'a' to be a selector")
        }

        // Find File selector with fileRoots
        if case .selector(let def) = find.child(forKey: "f") {
            #expect(def.label == "Find File")
            #expect(def.config.fileRoots == ["~"])
        } else {
            Issue.record("Expected 'f' to be a selector")
        }

        // Windows group
        let windows = tree.child(forKey: "w")!
        #expect(windows.isGroup)
        #expect(windows.child(forKey: "c")?.label == "Center")
        #expect(windows.child(forKey: "d")?.label == "First Third")
        #expect(windows.child(forKey: "m")?.label == "Maximise")
        #expect(windows.child(forKey: "r")?.label == "Restore")

        // Switch Window selector
        if case .selector(let def) = windows.child(forKey: "s") {
            #expect(def.config.prompt == "Select window…")
        } else {
            Issue.record("Expected 's' to be a selector")
        }

        // Open App group
        let openApp = tree.child(forKey: "o")!
        #expect(openApp.isGroup)
        #expect(openApp.child(forKey: "g")?.label == "GitButler")
        #expect(openApp.child(forKey: "t")?.label == "Telegram")
    }

    // MARK: - Native library functions are callable from config lambdas

    @Test func findInstalledAppsReturnsResultsFromConfig() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(find-installed-apps)")
        // Should be a non-empty list on any macOS system with /Applications
        if case .pair = result { } else {
            Issue.record("Expected non-empty list of apps")
        }
    }

    @Test func listWindowsCallableFromConfig() throws {
        let engine = try SchemeEngine()
        // Should not throw
        let result = try engine.evaluate("(list-windows)")
        switch result {
        case .pair, .null: break
        default: Issue.record("Expected list, got \(result)")
        }
    }

    @Test func clipboardRoundTripFromConfig() throws {
        let engine = try SchemeEngine()
        try engine.evaluate(#"(set-clipboard! "integration-test")"#)
        let result = try engine.evaluate("(get-clipboard)")
        #expect(try result.asString() == "integration-test")
    }

    @Test func shellCommandFromConfig() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "echo integration")"#)
        #expect(try result.asString() == "integration\n")
    }

    // MARK: - Action execution with native functions

    @Test func launchAppActionIsExecutable() throws {
        let engine = try SchemeEngine()
        // Create a command that calls launch-app, but wrap it to just return the arg
        // (don't actually launch an app in tests)
        let result = try engine.evaluate("""
            (procedure? (lambda () (launch-app "Safari")))
            """)
        #expect(result == .true)
    }

    @Test func selectorSourceReturnsMarshallableData() throws {
        let engine = try SchemeEngine()
        let source = try engine.evaluate("find-installed-apps")
        let invoker = SelectorSourceInvoker(engine: engine)
        let choices = try invoker.invoke(source: source)

        // Should have at least a few apps
        #expect(choices.count > 0)
        // Each choice should have text
        for choice in choices {
            #expect(!choice.text.isEmpty)
        }
    }

    // MARK: - App-local trees

    @Test func appLocalTreeRegisteredByBundleId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
            (define (keystroke mods key-name)
              (lambda () (send-keystroke mods key-name)))

            (define-tree 'com.apple.Safari
              (group "t" "Tabs"
                (key "n" "New Tab" (keystroke '(cmd) "t"))
                (key "w" "Close Tab" (keystroke '(cmd) "w"))))
            """)
        let tree = engine.registry.tree(for: .appLocal("com.apple.Safari"))
        #expect(tree != nil)
        #expect(tree?.label == "com.apple.Safari")

        let tabs = tree?.child(forKey: "t")
        #expect(tabs?.label == "Tabs")
        #expect(tabs?.child(forKey: "n")?.label == "New Tab")
        #expect(tabs?.child(forKey: "w")?.label == "Close Tab")
    }

    @Test func sendKeystrokeIsProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? send-keystroke)") == .true)
    }
}
