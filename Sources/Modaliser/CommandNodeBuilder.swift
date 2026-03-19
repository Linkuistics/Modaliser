import LispKit

/// Converts Scheme alists (produced by the DSL functions) into Swift CommandNode objects.
/// Used by `define-tree` to bridge the Scheme config into the typed Swift command tree.
struct CommandNodeBuilder {
    let symbols: SymbolTable

    /// Recursively convert a Scheme alist to a CommandNode.
    func buildNode(from expr: Expr) throws -> CommandNode {
        let kind = try lookupRequired(expr, key: "kind")
        guard case .symbol(let kindSym) = kind else {
            throw RuntimeError.type(kind, expected: [.symbolType])
        }
        let key = try lookupRequired(expr, key: "key").asString()
        let label = try lookupRequired(expr, key: "label").asString()

        switch kindSym.identifier {
        case "command":
            let action = try lookupRequired(expr, key: "action")
            return .command(CommandDefinition(key: key, label: label, action: action))

        case "group":
            let childrenList = try lookupRequired(expr, key: "children")
            var children: [String: CommandNode] = [:]
            var current = childrenList
            while case .pair(let head, let tail) = current {
                let child = try buildNode(from: head)
                children[child.key] = child
                current = tail
            }
            return .group(GroupDefinition(key: key, label: label, children: children))

        case "selector":
            // TODO: Parse 'actions' list and 'file-roots' when chooser UI is built (Session 5)
            let config = SelectorConfig(
                prompt: try? lookupRequired(expr, key: "prompt").asString(),
                source: lookupOptional(expr, key: "source"),
                onSelect: lookupOptional(expr, key: "on-select"),
                remember: try? lookupRequired(expr, key: "remember").asString(),
                idField: try? lookupRequired(expr, key: "id-field").asString(),
                actions: [],
                fileRoots: nil
            )
            return .selector(SelectorDefinition(key: key, label: label, config: config))

        default:
            throw RuntimeError.type(kind, expected: [.symbolType])
        }
    }

    /// Look up a required key in a Scheme alist. Throws a descriptive error if not found.
    private func lookupRequired(_ alist: Expr, key: String) throws -> Expr {
        let sym = symbols.intern(key)
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), let value) = entry, s == sym {
                return value
            }
            current = tail
        }
        throw RuntimeError.custom(
            "eval",
            "required key '\(key)' not found in DSL alist",
            [.symbol(sym)]
        )
    }

    /// Look up an optional key in a Scheme alist. Returns nil if not found.
    private func lookupOptional(_ alist: Expr, key: String) -> Expr? {
        let sym = symbols.intern(key)
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), let value) = entry, s == sym {
                return value
            }
            current = tail
        }
        return nil
    }
}
