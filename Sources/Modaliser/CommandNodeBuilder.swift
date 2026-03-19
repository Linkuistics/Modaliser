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
            let config = SelectorConfig(
                prompt: try? lookupRequired(expr, key: "prompt").asString(),
                source: lookupOptional(expr, key: "source"),
                onSelect: lookupOptional(expr, key: "on-select"),
                remember: try? lookupRequired(expr, key: "remember").asString(),
                idField: try? lookupRequired(expr, key: "id-field").asString(),
                actions: parseActions(from: lookupOptional(expr, key: "actions")),
                fileRoots: parseFileRoots(from: lookupOptional(expr, key: "file-roots"))
            )
            return .selector(SelectorDefinition(key: key, label: label, config: config))

        default:
            throw RuntimeError.type(kind, expected: [.symbolType])
        }
    }

    /// Parse a Scheme list of action alists into [ActionConfig].
    private func parseActions(from expr: Expr?) -> [ActionConfig] {
        guard let expr = expr else { return [] }
        var actions: [ActionConfig] = []
        var current = expr
        while case .pair(let head, let tail) = current {
            if let action = parseOneAction(from: head) {
                actions.append(action)
            }
            current = tail
        }
        return actions
    }

    private func parseOneAction(from alist: Expr) -> ActionConfig? {
        guard let name = try? lookupRequired(alist, key: "name").asString() else { return nil }
        let description = try? lookupRequired(alist, key: "description").asString()
        let run = lookupOptional(alist, key: "run") ?? .null
        let trigger = parseActionTrigger(from: lookupOptional(alist, key: "key"))
        return ActionConfig(name: name, description: description, trigger: trigger, run: run)
    }

    private func parseActionTrigger(from expr: Expr?) -> ActionTrigger? {
        guard case .symbol(let sym) = expr else { return nil }
        switch sym.identifier {
        case "primary": return .primary
        case "secondary": return .secondary
        default: return nil
        }
    }

    /// Parse a Scheme list of strings into [String] for file-roots.
    private func parseFileRoots(from expr: Expr?) -> [String]? {
        guard let expr = expr else { return nil }
        var roots: [String] = []
        var current = expr
        while case .pair(let head, let tail) = current {
            if let s = try? head.asString() {
                roots.append(s)
            }
            current = tail
        }
        return roots.isEmpty ? nil : roots
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
