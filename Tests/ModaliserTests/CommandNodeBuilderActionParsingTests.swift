import Testing
import LispKit
@testable import Modaliser

@Suite("CommandNodeBuilder Action Parsing")
struct CommandNodeBuilderActionParsingTests {

    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    // MARK: - Actions list parsing

    @Test func selectorWithActionsListParsesActions() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'source (lambda () '())
                  'on-select (lambda (c) c)
                  'actions
                    (list
                      (action "Open" 'key 'primary 'run (lambda (c) c))
                      (action "Show in Finder" 'key 'secondary 'run (lambda (c) c))
                      (action "Copy Path" 'run (lambda (c) c))))))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "a") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        #expect(def.config.actions.count == 3)
        #expect(def.config.actions[0].name == "Open")
        #expect(def.config.actions[0].trigger == .primary)
        #expect(def.config.actions[1].name == "Show in Finder")
        #expect(def.config.actions[1].trigger == .secondary)
        #expect(def.config.actions[2].name == "Copy Path")
        #expect(def.config.actions[2].trigger == nil)
    }

    @Test func selectorWithEmptyActionsListParsesEmpty() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Apps"
                  'prompt "Find…"
                  'actions (list))))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "a") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        #expect(def.config.actions.isEmpty)
    }

    @Test func selectorWithoutActionsParsesEmpty() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Apps" 'prompt "Find…")))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "a") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        #expect(def.config.actions.isEmpty)
    }

    @Test func actionRunFieldIsAProcedure() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Apps"
                  'prompt "Find…"
                  'actions
                    (list (action "Open" 'run (lambda (c) c))))))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "a") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        if case .procedure = def.config.actions[0].run {
            // expected — it's a Scheme procedure
        } else {
            #expect(Bool(false), "Expected procedure for action run")
        }
    }

    // MARK: - File roots parsing

    @Test func selectorWithFileRootsParsesPaths() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "f" "Files"
                  'prompt "Find file…"
                  'file-roots '("~" "/tmp"))))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "f") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        #expect(def.config.fileRoots == ["~", "/tmp"])
    }

    @Test func selectorWithoutFileRootsReturnsNil() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Apps" 'prompt "Find…")))
            """)
        let tree = engine.registry.tree(for: .global)
        let find = tree?.child(forKey: "f")
        guard case .selector(let def) = find?.child(forKey: "a") else {
            #expect(Bool(false), "Expected selector node")
            return
        }
        #expect(def.config.fileRoots == nil)
    }
}
