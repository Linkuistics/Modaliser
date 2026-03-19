import LispKit

/// A node in the modal command tree.
/// Commands execute actions, groups contain children, selectors present choosers.
enum CommandNode {
    case command(CommandDefinition)
    case group(GroupDefinition)
    case selector(SelectorDefinition)

    /// The single-character key that triggers this node.
    var key: String {
        switch self {
        case .command(let def): def.key
        case .group(let def): def.key
        case .selector(let def): def.key
        }
    }

    /// Human-readable label for display in the overlay.
    var label: String {
        switch self {
        case .command(let def): def.label
        case .group(let def): def.label
        case .selector(let def): def.label
        }
    }

    /// Look up a child node by key. Only valid for group nodes.
    func child(forKey key: String) -> CommandNode? {
        guard case .group(let def) = self else { return nil }
        return def.children[key]
    }

    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }

    var isSelector: Bool {
        if case .selector = self { return true }
        return false
    }
}

/// A leaf command that executes a Scheme lambda.
struct CommandDefinition {
    let key: String
    let label: String
    let action: Expr
}

/// A group of child command nodes, navigated by pressing the group's key.
struct GroupDefinition {
    let key: String
    let label: String
    let children: [String: CommandNode]
}

/// A selector that presents a searchable chooser UI.
struct SelectorDefinition {
    let key: String
    let label: String
    let config: SelectorConfig
}

/// Configuration for a selector's chooser behavior.
struct SelectorConfig {
    let prompt: String?
    let source: Expr?
    let onSelect: Expr?
    let remember: String?
    let idField: String?
    let actions: [ActionConfig]
    let fileRoots: [String]?
}

/// An action available in a selector's action panel.
struct ActionConfig {
    let name: String
    let trigger: ActionTrigger?
    let run: Expr
}

/// How a selector action is triggered.
enum ActionTrigger: Equatable {
    /// Return key (primary action)
    case primary
    /// Cmd+Return (secondary action)
    case secondary
}
