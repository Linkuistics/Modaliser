import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("Config loading end-to-end")
struct ConfigLoadingTests {

    private func writeConfigFile(_ content: String) throws -> (String, () -> Void) {
        let dir = NSTemporaryDirectory()
        let path = dir + "test-config-\(ProcessInfo.processInfo.globallyUniqueString).scm"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return (path, { try? FileManager.default.removeItem(atPath: path) })
    }

    @Test func loadMinimalConfig() throws {
        let (path, cleanup) = try writeConfigFile("""
            (set-leader! 'global 79)
            (set-leader! 'local 64)

            (define-tree 'global
              (key "s" "Safari" (lambda () #t))
              (group "f" "Find"
                (key "a" "Apps" (lambda () #t))
                (key "f" "Files" (lambda () #t)))
              (group "w" "Windows"
                (key "c" "Center" (lambda () #t))
                (key "m" "Maximize" (lambda () #t))))
            """)
        defer { cleanup() }

        let engine = try SchemeEngine()
        try engine.evaluateFile(path)

        // Leader keys
        #expect(engine.registry.leaderKey(for: .global) == 79)
        #expect(engine.registry.leaderKey(for: .local) == 64)

        // Tree structure
        let tree = engine.registry.tree(for: .global)
        #expect(tree != nil)
        #expect(tree?.label == "Global")

        // Direct command
        let safari = tree?.child(forKey: "s")
        #expect(safari?.label == "Safari")
        #expect(safari?.isCommand == true)

        // Group with children
        let find = tree?.child(forKey: "f")
        #expect(find?.label == "Find")
        #expect(find?.isGroup == true)
        #expect(find?.child(forKey: "a")?.label == "Apps")
        #expect(find?.child(forKey: "f")?.label == "Files")

        // Second group
        let windows = tree?.child(forKey: "w")
        #expect(windows?.label == "Windows")
        #expect(windows?.child(forKey: "c")?.label == "Center")
        #expect(windows?.child(forKey: "m")?.label == "Maximize")
    }

    @Test func loadConfigWithSelector() throws {
        let (path, cleanup) = try writeConfigFile("""
            (define-tree 'global
              (key "s" "Safari" (lambda () #t))
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'remember "apps"
                  'id-field "bundleId")))
            """)
        defer { cleanup() }

        let engine = try SchemeEngine()
        try engine.evaluateFile(path)

        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        let apps = find?.child(forKey: "a")
        #expect(apps?.label == "Find Apps")
        #expect(apps?.isSelector == true)

        // Verify selector config was parsed
        if case .selector(let def) = apps {
            #expect(def.config.prompt == "Find app…")
            #expect(def.config.remember == "apps")
            #expect(def.config.idField == "bundleId")
        } else {
            #expect(Bool(false), "Expected selector node")
        }
    }

    @Test func loadConfigWithDefinedHelpers() throws {
        let (path, cleanup) = try writeConfigFile("""
            ;; User-defined helper function
            (define (make-launcher app-name)
              (lambda () (list 'launch app-name)))

            (define-tree 'global
              (key "s" "Safari" (make-launcher "Safari"))
              (key "t" "Terminal" (make-launcher "Terminal")))
            """)
        defer { cleanup() }

        let engine = try SchemeEngine()
        try engine.evaluateFile(path)

        let tree = engine.registry.tree(for: .global)
        #expect(tree?.child(forKey: "s")?.label == "Safari")
        #expect(tree?.child(forKey: "t")?.label == "Terminal")

        // Verify the stored action is a callable procedure
        if case .command(let def) = tree?.child(forKey: "s") {
            if case .procedure = def.action {
                // Expected — action is a Scheme procedure
            } else {
                #expect(Bool(false), "Expected procedure, got \(def.action)")
            }
        }
    }
}
