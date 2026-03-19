import Testing
import LispKit
@testable import Modaliser

@Suite("DSL Library")
struct DSLLibraryTests {

    // Helper: create engine with DSL library loaded
    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    // MARK: - key function

    @Test func keyReturnsAlistWithKindCommand() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (key "s" "Safari" (lambda () #t))
            """)
        // Result should be an alist with (kind . command)
        let kind = try engine.evaluate("(cdr (assoc 'kind (key \"s\" \"Safari\" (lambda () #t))))")
        #expect(kind == .symbol(engine.context.symbols.intern("command")))
    }

    @Test func keyAlistContainsKeyAndLabel() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define result (key \"s\" \"Safari\" (lambda () #t)))")
        let key = try engine.evaluate("(cdr (assoc 'key result))")
        let label = try engine.evaluate("(cdr (assoc 'label result))")
        #expect(key == .makeString("s"))
        #expect(label == .makeString("Safari"))
    }

    @Test func keyAlistContainsAction() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define result (key \"x\" \"Test\" (lambda () 42)))")
        let action = try engine.evaluate("(cdr (assoc 'action result))")
        // Action should be a procedure
        if case .procedure = action {
            // expected
        } else {
            #expect(Bool(false), "Expected procedure, got \(action)")
        }
    }

    // MARK: - group function

    @Test func groupReturnsAlistWithKindGroup() throws {
        let engine = try makeEngine()
        let kind = try engine.evaluate("""
            (cdr (assoc 'kind (group "f" "Find"
              (key "a" "Apps" (lambda () #t)))))
            """)
        #expect(kind == .symbol(engine.context.symbols.intern("group")))
    }

    @Test func groupAlistContainsChildren() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define result (group "f" "Find"
              (key "a" "Apps" (lambda () #t))
              (key "b" "Browser" (lambda () #t))))
            """)
        _ = try engine.evaluate("(cdr (assoc 'children result))")
        // Children should be a list of two items
        let len = try engine.evaluate("(length (cdr (assoc 'children result)))")
        #expect(len == .fixnum(2))
    }

    // MARK: - selector function

    @Test func selectorReturnsAlistWithKindSelector() throws {
        let engine = try makeEngine()
        let kind = try engine.evaluate("""
            (cdr (assoc 'kind (selector "a" "Find Apps"
              'prompt "Find app…")))
            """)
        #expect(kind == .symbol(engine.context.symbols.intern("selector")))
    }

    @Test func selectorParsesPropertyArguments() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define result (selector "a" "Find Apps"
              'prompt "Find app…"
              'remember "apps"
              'id-field "bundleId"))
            """)
        let prompt = try engine.evaluate("(cdr (assoc 'prompt result))")
        let remember = try engine.evaluate("(cdr (assoc 'remember result))")
        let idField = try engine.evaluate("(cdr (assoc 'id-field result))")
        #expect(prompt == .makeString("Find app…"))
        #expect(remember == .makeString("apps"))
        #expect(idField == .makeString("bundleId"))
    }

    // MARK: - action function

    @Test func actionReturnsAlistWithNameAndRun() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define result (action "Open" 'key 'primary 'run (lambda (c) c)))
            """)
        let name = try engine.evaluate("(cdr (assoc 'name result))")
        let key = try engine.evaluate("(cdr (assoc 'key result))")
        #expect(name == .makeString("Open"))
        #expect(key == .symbol(engine.context.symbols.intern("primary")))
    }

    // MARK: - define-tree

    @Test func defineTreeRegistersGlobalTree() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)
        let tree = engine.registry.tree(for: .global)
        #expect(tree != nil)
        #expect(tree?.label == "Global")
    }

    @Test func defineTreeChildrenAreAccessible() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () #t))
              (group "f" "Find"
                (key "a" "Apps" (lambda () #t))))
            """)
        let tree = engine.registry.tree(for: .global)
        let safari = tree?.child(forKey: "s")
        #expect(safari?.label == "Safari")
        #expect(safari?.isCommand == true)

        let find = tree?.child(forKey: "f")
        #expect(find?.label == "Find")
        #expect(find?.isGroup == true)

        let apps = find?.child(forKey: "a")
        #expect(apps?.label == "Apps")
    }

    // MARK: - set-leader!

    @Test func setLeaderRegistersKeyCode() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(set-leader! 'global F18)")
        #expect(engine.registry.leaderKey(for: .global) == KeyCode.f18)
    }

    @Test func setLeaderSupportsLocalMode() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(set-leader! 'local F17)")
        #expect(engine.registry.leaderKey(for: .local) == KeyCode.f17)
    }

    // MARK: - Key code constants

    @Test func keyCodeConstantsAreExposed() throws {
        let engine = try makeEngine()
        #expect(try engine.evaluate("F17") == .fixnum(Int64(KeyCode.f17)))
        #expect(try engine.evaluate("F18") == .fixnum(Int64(KeyCode.f18)))
        #expect(try engine.evaluate("F19") == .fixnum(Int64(KeyCode.f19)))
        #expect(try engine.evaluate("F20") == .fixnum(Int64(KeyCode.f20)))
    }

    // MARK: - set-theme!

    @Test func setThemeRegistersCustomTheme() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (set-theme!
              'font "Monaco"
              'font-size 14
              'overlay-width 400)
            """)
        let theme = engine.registry.theme
        #expect(theme != nil)
        #expect(theme?.fontSize == 14)
        #expect(theme?.overlayWidth == 400)
    }

    @Test func setThemeWithColorsRegistersTheme() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (set-theme!
              'bg '(0.1 0.1 0.1)
              'accent '(1.0 0.0 0.0))
            """)
        let theme = engine.registry.theme
        #expect(theme != nil)
    }

    @Test func setThemeWithShowDelayRegistersTheme() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (set-theme!
              'show-delay 0.5)
            """)
        let theme = engine.registry.theme
        #expect(theme?.showDelay == 0.5)
    }

    @Test func setThemeWithoutArgsUsesDefaults() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(set-theme!)")
        let theme = engine.registry.theme
        #expect(theme != nil)
        #expect(theme?.fontSize == OverlayTheme.default.fontSize)
    }
}
