import CoreGraphics
import LispKit

/// Native LispKit library providing the Modaliser DSL functions.
/// Scheme name: (modaliser dsl)
///
/// Provides: key, group, selector, action, define-tree, set-leader!
/// Also exports key code constants: F17, F18, F19, F20
///
/// DSL functions (key, group, selector, action) return Scheme alists.
/// define-tree converts alists into Swift CommandNode objects and registers them.
final class ModaliserDSLLibrary: NativeLibrary {

    /// Injected after init by SchemeEngine. Required because NativeLibrary
    /// mandates a `required init(in:)` with no room for extra parameters.
    var registry: CommandTreeRegistry?

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "dsl"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define", "quote", "lambda", "list", "cons",
                      "car", "cdr", "pair?", "null?", "symbol?", "string?", "number?",
                      "eq?", "equal?", "assoc", "append", "length")
    }

    public override func declarations() {
        // DSL functions
        self.define(Procedure("key", self.keyFunction))
        self.define(Procedure("group", self.groupFunction))
        self.define(Procedure("selector", self.selectorFunction))
        self.define(Procedure("action", self.actionFunction))
        self.define(Procedure("define-tree", self.defineTreeFunction))
        self.define(Procedure("set-leader!", self.setLeaderFunction))
        self.define(Procedure("set-theme!", self.setThemeFunction))
        // Key code constants
        self.define("F17", as: .fixnum(Int64(KeyCode.f17)))
        self.define("F18", as: .fixnum(Int64(KeyCode.f18)))
        self.define("F19", as: .fixnum(Int64(KeyCode.f19)))
        self.define("F20", as: .fixnum(Int64(KeyCode.f20)))
    }

    // MARK: - DSL functions

    /// (key "s" "Safari" (lambda () ...)) → alist
    private func keyFunction(_ keyStr: Expr, _ label: Expr, _ action: Expr) throws -> Expr {
        let k = try keyStr.asString()
        let l = try label.asString()
        return makeAlist([
            ("kind", .symbol(self.context.symbols.intern("command"))),
            ("key", .makeString(k)),
            ("label", .makeString(l)),
            ("action", action),
        ])
    }

    /// (group "f" "Find" child1 child2 ...) → alist
    private func groupFunction(_ keyStr: Expr, _ label: Expr, _ rest: Arguments) throws -> Expr {
        let k = try keyStr.asString()
        let l = try label.asString()
        return makeAlist([
            ("kind", .symbol(self.context.symbols.intern("group"))),
            ("key", .makeString(k)),
            ("label", .makeString(l)),
            ("children", .makeList(rest)),
        ])
    }

    /// (selector "a" "Find Apps" 'prompt "Find app…" 'source fn ...) → alist
    private func selectorFunction(_ keyStr: Expr, _ label: Expr, _ rest: Arguments) throws -> Expr {
        let k = try keyStr.asString()
        let l = try label.asString()
        var entries: [(String, Expr)] = [
            ("kind", .symbol(self.context.symbols.intern("selector"))),
            ("key", .makeString(k)),
            ("label", .makeString(l)),
        ]
        parsePropertyArguments(from: rest, into: &entries)
        return makeAlist(entries)
    }

    /// (action "Open" 'key 'primary 'run (lambda (c) ...)) → alist
    private func actionFunction(_ nameStr: Expr, _ rest: Arguments) throws -> Expr {
        let n = try nameStr.asString()
        var entries: [(String, Expr)] = [
            ("name", .makeString(n)),
        ]
        parsePropertyArguments(from: rest, into: &entries)
        return makeAlist(entries)
    }

    /// (define-tree 'global child1 child2 ...) → void
    private func defineTreeFunction(_ mode: Expr, _ rest: Arguments) throws -> Expr {
        guard let registry else {
            throw RuntimeError.custom("eval", "DSL library not initialized (no registry)", [])
        }
        guard case .symbol(let modeSym) = mode else {
            throw RuntimeError.type(mode, expected: [.symbolType])
        }
        let scope: TreeScope
        let treeLabel: String
        switch modeSym.identifier {
        case "global":
            scope = .global
            treeLabel = "Global"
        default:
            scope = .appLocal(modeSym.identifier)
            treeLabel = modeSym.identifier
        }
        let builder = CommandNodeBuilder(symbols: self.context.symbols)
        var children: [String: CommandNode] = [:]
        for childExpr in rest {
            let node = try builder.buildNode(from: childExpr)
            children[node.key] = node
        }
        let root = CommandNode.group(GroupDefinition(
            key: "",
            label: treeLabel,
            children: children
        ))
        registry.registerTree(for: scope, root: root)
        return .void
    }

    /// (set-leader! 'global F18) → void
    private func setLeaderFunction(_ mode: Expr, _ keyCode: Expr) throws -> Expr {
        guard let registry else {
            throw RuntimeError.custom("eval", "DSL library not initialized (no registry)", [])
        }
        guard case .symbol(let modeSym) = mode else {
            throw RuntimeError.type(mode, expected: [.symbolType])
        }
        let code = try keyCode.asInt64()
        let leaderMode: LeaderMode = modeSym.identifier == "global" ? .global : .local
        registry.setLeaderKey(for: leaderMode, keyCode: CGKeyCode(code))
        return .void
    }

    /// (set-theme! 'font "Monaco" 'font-size 14 'bg '(0.1 0.1 0.1) ...) → void
    private func setThemeFunction(_ rest: Arguments) throws -> Expr {
        guard let registry else {
            throw RuntimeError.custom("eval", "DSL library not initialized (no registry)", [])
        }
        var props: [(String, Expr)] = []
        parsePropertyArguments(from: rest, into: &props)
        registry.theme = ThemeConfigParser().parseTheme(from: props)
        return .void
    }

    // MARK: - Helpers

    /// Parse alternating 'symbol value pairs from rest arguments.
    private func parsePropertyArguments(from args: Arguments, into entries: inout [(String, Expr)]) {
        var i = args.startIndex
        while i < args.endIndex {
            guard case .symbol(let sym) = args[i] else {
                i = args.index(after: i)
                continue
            }
            let nextIndex = args.index(after: i)
            guard nextIndex < args.endIndex else { break }
            entries.append((sym.identifier, args[nextIndex]))
            i = args.index(after: nextIndex)
        }
    }

    /// Build a Scheme alist from Swift key-value pairs.
    private func makeAlist(_ entries: [(String, Expr)]) -> Expr {
        SchemeAlistLookup.makeAlist(entries, symbols: self.context.symbols)
    }
}
